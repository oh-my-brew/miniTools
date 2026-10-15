import AppKit
import Foundation
import UniformTypeIdentifiers

struct DefaultApplicationIdentity: Equatable, Sendable {
    let name: String
    let bundleIdentifier: String?
    let url: URL

    func matches(_ other: DefaultApplicationIdentity) -> Bool {
        if let bundleIdentifier, let otherBundleIdentifier = other.bundleIdentifier {
            return bundleIdentifier == otherBundleIdentifier
        }
        return url.standardizedFileURL == other.url.standardizedFileURL
    }
}

@MainActor
protocol DefaultApplicationClient: AnyObject {
    func sublimeTextApplication() -> DefaultApplicationIdentity?
    func defaultApplication(for contentType: UTType) -> DefaultApplicationIdentity?
    func setDefaultApplication(
        _ application: DefaultApplicationIdentity,
        for contentType: UTType
    ) async throws
}

@MainActor
final class NSWorkspaceDefaultApplicationClient: DefaultApplicationClient {
    private static let sublimeTextBundleIdentifiers = [
        "com.sublimetext.4",
        "com.sublimetext.3"
    ]

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func sublimeTextApplication() -> DefaultApplicationIdentity? {
        for bundleIdentifier in Self.sublimeTextBundleIdentifiers {
            guard let url = workspace.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                continue
            }
            return identity(for: url)
        }
        return nil
    }

    func defaultApplication(for contentType: UTType) -> DefaultApplicationIdentity? {
        guard let url = workspace.urlForApplication(toOpen: contentType) else {
            return nil
        }
        return identity(for: url)
    }

    func setDefaultApplication(
        _ application: DefaultApplicationIdentity,
        for contentType: UTType
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            workspace.setDefaultApplication(
                at: application.url,
                toOpen: contentType
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func identity(for url: URL) -> DefaultApplicationIdentity {
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        return DefaultApplicationIdentity(
            name: displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundle?.bundleIdentifier,
            url: url
        )
    }
}
