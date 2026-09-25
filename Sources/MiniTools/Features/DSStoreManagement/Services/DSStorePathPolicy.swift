import Foundation

enum DSStorePathPolicy {
    private static let excludedDirectoryNames: Set<String> = [
        ".Trash", ".Trashes", ".DocumentRevisions-V100", ".Spotlight-V100",
        ".TemporaryItems", ".fseventsd", "System", "Library", "Applications"
    ]

    private static let excludedSystemRoots: [String] = [
        "/System", "/Library", "/Applications", "/private", "/usr", "/bin", "/sbin", "/var"
    ]

    static func normalizedSelectableDirectory(_ url: URL) -> URL? {
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            return nil
        }
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        guard normalized.path != "/",
              !isSystemPath(normalized.path),
              isReadableDirectory(normalized),
              !isExcludedDirectory(normalized) else {
            return nil
        }
        return normalized
    }

    static func shouldSkipDirectory(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return true
        }
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        return isSystemPath(normalized.path)
            || isExcludedDirectory(normalized)
            || !isReadableDirectory(normalized)
    }

    static func isDSStore(_ url: URL) -> Bool {
        url.lastPathComponent == ".DS_Store"
    }

    static func canDelete(_ file: URL, below roots: [URL]) -> Bool {
        let normalizedFile = file.standardizedFileURL.resolvingSymlinksInPath()
        guard isDSStore(normalizedFile) else { return false }
        for root in roots {
            let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            guard normalizedFile.path.hasPrefix(normalizedRoot.path + "/") else { continue }
            var directory = normalizedFile.deletingLastPathComponent()
            while directory.path != normalizedRoot.path {
                if shouldSkipDirectory(directory) { return false }
                let parent = directory.deletingLastPathComponent()
                guard parent.path != directory.path else { return false }
                directory = parent
            }
            return !shouldSkipDirectory(normalizedRoot)
        }
        return false
    }

    private static func isSystemPath(_ path: String) -> Bool {
        excludedSystemRoots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    private static func isExcludedDirectory(_ url: URL) -> Bool {
        if excludedDirectoryNames.contains(url.lastPathComponent) { return true }
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isPackageKey, .isReadableKey]
        ) else {
            return true
        }
        return values.isDirectory != true || values.isPackage == true || values.isReadable == false
    }

    private static func isReadableDirectory(_ url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }
}

struct DSStoreEventDeduplicator {
    private var lastSeen: [String: TimeInterval] = [:]
    let interval: TimeInterval

    init(interval: TimeInterval = 1) {
        self.interval = interval
    }

    mutating func shouldProcess(path: String, now: TimeInterval) -> Bool {
        if let previous = lastSeen[path], now - previous < interval {
            return false
        }
        lastSeen[path] = now
        if lastSeen.count > 512 {
            lastSeen = lastSeen.filter { now - $0.value < interval }
        }
        return true
    }
}

struct DSStoreErrorRateLimiter {
    private var lastReportedAt: TimeInterval?
    let interval: TimeInterval

    init(interval: TimeInterval = 10) {
        self.interval = interval
    }

    mutating func shouldReport(now: TimeInterval) -> Bool {
        guard let lastReportedAt, now - lastReportedAt < interval else {
            lastReportedAt = now
            return true
        }
        return false
    }
}
