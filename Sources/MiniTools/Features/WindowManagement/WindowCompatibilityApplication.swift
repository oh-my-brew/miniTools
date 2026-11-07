import Foundation

/// Metadata only: selecting an application never launches it or loads executable code.
struct WindowCompatibilityApplication: Equatable {
    let bundleIdentifier: String
    let name: String

    init?(info: [String: Any]) {
        guard let identifier = info["CFBundleIdentifier"] as? String,
              Self.isValidBundleIdentifier(identifier),
              info["CFBundlePackageType"] as? String == "APPL" else { return nil }
        bundleIdentifier = identifier
        let names = [info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String]
        name = names.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? identifier
    }

    static func isValidBundleIdentifier(_ identifier: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return !identifier.isEmpty
            && identifier.unicodeScalars.allSatisfy { allowed.contains($0) }
            && identifier.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty }
    }

    static let defaultNames = [
        "com.apple.Safari": "Safari", "com.apple.finder": "Finder",
        "com.openai.codex": "Codex", "com.openai.chat": "ChatGPT",
        "com.tencent.qq": "QQ", "com.electron.lark": "飞书"
    ]
}
