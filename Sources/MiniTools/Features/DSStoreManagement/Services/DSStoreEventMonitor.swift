import CoreServices
import Foundation

final class DSStoreEventMonitor: @unchecked Sendable {
    var onDeleted: (@Sendable () -> Void)?
    var onError: (@Sendable (String) -> Void)?

    private let queue = DispatchQueue(label: "com.omzcj.minitools.ds-store-monitor")
    private var stream: FSEventStreamRef?
    private var roots: [URL] = []
    private var deduplicator = DSStoreEventDeduplicator()
    private var errorRateLimiter = DSStoreErrorRateLimiter()

    func start(directories: [URL]) -> Bool {
        queue.sync { startOnQueue(directories: directories) }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    private func startOnQueue(directories: [URL]) -> Bool {
        stopOnQueue()
        let paths = directories.compactMap(DSStorePathPolicy.normalizedMonitoredDirectory)
        guard !paths.isEmpty else { return false }
        roots = paths

        let callback: FSEventStreamCallback = { _, context, count, eventPaths, flags, _ in
            guard let context else { return }
            let monitor = Unmanaged<DSStoreEventMonitor>.fromOpaque(context).takeUnretainedValue()
            let pathArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            let paths = pathArray as? [String] ?? []
            monitor.process(paths: Array(paths.prefix(count)), flags: flags)
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let watchedPaths = paths.map(\.path) as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            watchedPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagIgnoreSelf
                    | kFSEventStreamCreateFlagUseCFTypes
            )
        ) else {
            roots = []
            return false
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            stopOnQueue()
            return false
        }
        return true
    }

    private func stopOnQueue() {
        guard let stream else {
            roots = []
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        roots = []
    }

    private func process(
        paths: [String],
        flags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        for (index, path) in paths.enumerated() {
            let eventFlags = flags[index]
            guard eventFlags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) == 0 else {
                continue
            }
            let eventURL = URL(fileURLWithPath: path)
            let candidate: URL
            if DSStorePathPolicy.isDSStore(eventURL) {
                candidate = eventURL
            } else {
                guard eventFlags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 else {
                    continue
                }
                candidate = eventURL.appendingPathComponent(".DS_Store", isDirectory: false)
            }
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            guard DSStorePathPolicy.canDelete(candidate, below: roots) else { continue }
            guard deduplicator.shouldProcess(path: candidate.path, now: now) else { continue }
            do {
                if try DSStoreCleaner.removeIfPresent(at: candidate) {
                    onDeleted?()
                }
            } catch {
                report("无法删除 \(candidate.path)：\(error.localizedDescription)", now: now)
            }
        }
    }

    private func report(_ message: String, now: TimeInterval) {
        guard errorRateLimiter.shouldReport(now: now) else { return }
        onError?(message)
    }

    deinit {
        queue.sync { stopOnQueue() }
    }
}
