import Foundation
import OSLog

/// Correlated action and read-only observation records; no titles or content.
final class WindowAdjustmentTrace {
    struct Event: Codable, Sendable {
        let phase: String
        let elapsedMS: Double
        let frame: [Double]?
        let axStatus: Int32?
    }

    struct Record: Codable, Sendable {
        let schema: Int
        var stage: String = "action"
        var observedAccessibility: [Double]?
        var observedWindowServer: [Double]?
        let id: UUID
        let timestamp: Date
        let version: String
        let build: String
        let command: String
        var processID: Int32?
        var application: String?
        var windowID: UInt32?
        var frameSource: String?
        var initial: [Double]?
        var target: [Double]?
        var visible: [Double]?
        var final: [Double]?
        var outcome: String
        var elapsedMS: Double
        var events: [Event]
    }

    private let started: TimeInterval
    private var record: Record

    init(command: String, requestedAt: TimeInterval) {
        started = requestedAt
        let queuedMS = max(0, (ProcessInfo.processInfo.systemUptime - requestedAt) * 1000)
        record = Record(
            schema: 1, id: UUID(), timestamp: Date().addingTimeInterval(-queuedMS / 1000),
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            command: command, outcome: "started", elapsedMS: 0, events: []
        )
        event("queued", elapsedMS: queuedMS)
    }

    func identify(processID: Int32, application: String?, windowID: UInt32?, frameSource: String) {
        record.processID = processID
        record.application = application
        record.windowID = windowID
        record.frameSource = frameSource
    }

    func plan(initial: CGRect, target: CGRect, visible: CGRect) {
        record.initial = Self.components(initial)
        record.target = Self.components(target)
        record.visible = Self.components(visible)
    }

    func event(_ phase: String, frame: CGRect? = nil, axStatus: Int32? = nil, elapsedMS: Double? = nil) {
        guard record.events.count < 64 else { return }
        record.events.append(Event(
            phase: phase,
            elapsedMS: elapsedMS ?? (ProcessInfo.processInfo.systemUptime - started) * 1000,
            frame: frame.map(Self.components), axStatus: axStatus
        ))
    }

    func finish(_ outcome: String, frame: CGRect? = nil) {
        record.outcome = outcome
        record.final = frame.map(Self.components)
        record.elapsedMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
        WindowAdjustmentLog.shared.append(record)
    }

    func snapshot() -> Record { record }

    static func appendObservation(from record: Record, phase: String, elapsedMS: Double,
                                  accessibility: CGRect?, windowServer: CGRect?) {
        var sample = record
        sample.stage = phase
        sample.elapsedMS = elapsedMS
        sample.observedAccessibility = accessibility.map(components)
        sample.observedWindowServer = windowServer.map(components)
        sample.final = (windowServer ?? accessibility).map(components)
        sample.events = []
        WindowAdjustmentLog.shared.append(sample)
    }

    private static func components(_ rect: CGRect) -> [Double] {
        [rect.minX, rect.minY, rect.width, rect.height].map { Double($0) }
    }
}

/// All filesystem work is off the AX queue. Two files, each at most 2 MiB.
private final class WindowAdjustmentLog: @unchecked Sendable {
    static let shared = WindowAdjustmentLog()
    private let queue = DispatchQueue(label: "com.omzcj.minitools.window-diagnostics", qos: .utility)
    private let logger = Logger(subsystem: "com.omzcj.minitools", category: "WindowManagement")
    private let maximumBytes = 2 * 1024 * 1024

    func append(_ record: WindowAdjustmentTrace.Record) {
        // Serialize before crossing queues; the trace itself stays on its worker.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0a)
        let line = data
        queue.async { [self] in
            do {
                let manager = FileManager.default
                let directory = manager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/miniTools", isDirectory: true)
                try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
                let current = directory.appendingPathComponent("window-management.jsonl")
                let previous = directory.appendingPathComponent("window-management.previous.jsonl")
                let attributes = try? manager.attributesOfItem(atPath: current.path)
                let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                if bytes + line.count > maximumBytes {
                    if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                    if manager.fileExists(atPath: current.path) { try manager.moveItem(at: current, to: previous) }
                }
                if !manager.fileExists(atPath: current.path) {
                    guard manager.createFile(atPath: current.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else { return }
                }
                let handle = try FileHandle(forWritingTo: current)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } catch {
                logger.error("Unable to append window adjustment diagnostics")
            }
        }
    }
}
