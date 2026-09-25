import Foundation
import XCTest
@testable import MiniTools

final class DSStoreManagementTests: XCTestCase {
    func testEventDeduplicatorSuppressesRepeatedPathWithinInterval() {
        var deduplicator = DSStoreEventDeduplicator(interval: 1)

        XCTAssertTrue(deduplicator.shouldProcess(path: "/tmp/a/.DS_Store", now: 10))
        XCTAssertFalse(deduplicator.shouldProcess(path: "/tmp/a/.DS_Store", now: 10.5))
        XCTAssertTrue(deduplicator.shouldProcess(path: "/tmp/a/.DS_Store", now: 11))
        XCTAssertTrue(deduplicator.shouldProcess(path: "/tmp/b/.DS_Store", now: 10.5))
    }

    func testErrorRateLimiterReportsAtMostOncePerInterval() {
        var limiter = DSStoreErrorRateLimiter(interval: 10)

        XCTAssertTrue(limiter.shouldReport(now: 20))
        XCTAssertFalse(limiter.shouldReport(now: 29.9))
        XCTAssertTrue(limiter.shouldReport(now: 30))
    }

    func testPathPolicyRejectsRootAndSystemDirectories() {
        XCTAssertNil(DSStorePathPolicy.normalizedSelectableDirectory(URL(fileURLWithPath: "/")))
        XCTAssertNil(DSStorePathPolicy.normalizedSelectableDirectory(URL(fileURLWithPath: "/System")))
        XCTAssertNil(DSStorePathPolicy.normalizedSelectableDirectory(URL(fileURLWithPath: "/Applications")))
    }

    func testCleanerCountsOnlySuccessfullyDeletedFilesAndSkipsPackages() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("MiniToolsDSStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Folder", isDirectory: true)
        let package = root.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let removable = directory.appendingPathComponent(".DS_Store")
        let excluded = package.appendingPathComponent(".DS_Store")
        XCTAssertTrue(FileManager.default.createFile(atPath: removable.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: excluded.path, contents: Data()))

        let result = DSStoreCleaner.clean(directories: [root])

        XCTAssertEqual(result.deletedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: removable.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: excluded.path))
    }

    func testPathPolicyDoesNotAllowDeletionOutsideSelectedRoot() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("MiniToolsDSStoreRoot-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("MiniToolsDSStoreOutside-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".DS_Store")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        XCTAssertFalse(DSStorePathPolicy.canDelete(outside, below: [root]))
        XCTAssertTrue(
            DSStorePathPolicy.canDelete(
                root.appendingPathComponent(".DS_Store"),
                below: [root]
            )
        )
    }
}
