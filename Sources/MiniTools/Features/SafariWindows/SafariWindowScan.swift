import Foundation

/// A cancelled AX call may finish later. Chain scans so reopening never overlaps AX walks.
actor SafariWindowScanWorker {
    private var tail: Task<[SafariWindowItem], Error>?
    private var requestID: UUID?

    func fetch(_ operation: @escaping @Sendable () throws -> [SafariWindowItem]) async throws -> [SafariWindowItem] {
        try Task.checkCancellation()
        let previous = tail
        previous?.cancel()
        let id = UUID()
        let task = Task.detached(priority: .userInitiated) {
            if let previous { _ = await previous.result }
            try Task.checkCancellation()
            return try operation()
        }
        tail = task
        requestID = id
        defer {
            if requestID == id { tail = nil; requestID = nil }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

struct SafariWindowScanBudget {
    private let deadline: ContinuousClock.Instant

    init(timeout: Duration = .seconds(2)) {
        deadline = .now.advanced(by: timeout)
    }

    func check() throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else {
            throw MiniToolsError.processingFailed("Safari 响应较慢，请稍后重新打开窗口列表")
        }
    }
}

struct SafariTreeNode<Node> {
    let role: String?
    let title: String?
    let description: String?
    let children: [Node]
    var webTitle: String? {
        guard role == "AXWebArea" else { return nil }
        return [title, description].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

enum SafariWebAreaLocator {
    /// Paths contain child indexes, never retained AX elements from a previous session.
    static func locate<Node>(root: Node, cachedPath: [Int]?,
                             read: (Node) throws -> SafariTreeNode<Node>,
                             check: () throws -> Void) throws -> (title: String, path: [Int])? {
        if let cachedPath {
            var node = root
            var valid = true
            for index in cachedPath {
                try check()
                let info = try read(node)
                guard info.children.indices.contains(index) else { valid = false; break }
                node = info.children[index]
            }
            if valid {
                try check()
                if let title = try read(node).webTitle { return (title, cachedPath) }
            }
        }
        var queue: [(Node, [Int])] = [(root, [])]
        var cursor = 0
        while cursor < queue.count, cursor < 250 {
            try check()
            let (node, path) = queue[cursor]
            cursor += 1
            let info = try read(node)
            if let title = info.webTitle { return (title, path) }
            guard path.count < 8 else { continue }
            // Cap the queue as well as visited nodes for unusually large AX child arrays.
            let remaining = max(0, 250 - queue.count)
            queue.append(contentsOf: info.children.prefix(remaining).enumerated().map { ($0.element, path + [$0.offset]) })
        }
        return nil
    }
}

final class SafariWindowPathCache: @unchecked Sendable {
    private let lock = NSLock()
    struct Entry {
        let title: String
        let path: [Int]
    }

    private var process: String?
    private var paths: [String: Entry] = [:]

    func snapshot(for pid: String) -> [String: Entry] {
        lock.withLock { process == pid ? paths : [:] }
    }

    func replace(_ paths: [String: Entry], for pid: String) {
        lock.withLock { self.process = pid; self.paths = paths }
    }
}
