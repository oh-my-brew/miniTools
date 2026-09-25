import Foundation

struct DSStoreCleanupResult: Sendable {
    let deletedCount: Int
    let lastError: String?
}

enum DSStoreCleaner {
    static func clean(directories: [URL]) -> DSStoreCleanupResult {
        var deletedCount = 0
        let errorStore = DSStoreCleanupErrorStore()

        for directory in directories {
            guard let root = DSStorePathPolicy.normalizedMonitoredDirectory(directory) else {
                errorStore.set("无法访问目录：\(directory.path)")
                continue
            }
            let keys: [URLResourceKey] = [
                .isDirectoryKey, .isPackageKey, .isReadableKey, .isSymbolicLinkKey
            ]
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { url, error in
                    errorStore.set("无法读取 \(url.path)：\(error.localizedDescription)")
                    return true
                }
            ) else {
                errorStore.set("无法读取目录：\(root.path)")
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                   DSStorePathPolicy.shouldSkipDirectory(url) {
                    enumerator.skipDescendants()
                    continue
                }
                guard DSStorePathPolicy.isDSStore(url) else { continue }
                do {
                    try FileManager.default.removeItem(at: url)
                    deletedCount += 1
                } catch let error as CocoaError where error.code == .fileNoSuchFile {
                    continue
                } catch {
                    errorStore.set("无法删除 \(url.path)：\(error.localizedDescription)")
                }
            }
        }
        return DSStoreCleanupResult(deletedCount: deletedCount, lastError: errorStore.value)
    }

    static func removeIfPresent(at url: URL) throws -> Bool {
        guard DSStorePathPolicy.isDSStore(url),
              FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return false
        }
    }
}

private final class DSStoreCleanupErrorStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: String?

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: String) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}
