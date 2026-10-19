import Foundation

/// The round identifies the immutable Beta build, including after same-ZIP promotion.
enum AppVersion {
    static var displayName: String {
        displayName(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    static func displayName(version: String?, build: String?) -> String {
        guard let version, !version.isEmpty else { return "开发构建" }
        let parts = version.split(separator: ".")
        let buildParts = (build ?? "").split(separator: ".")
        guard parts.count == 4, buildParts.count == 3,
              buildParts[0] == parts[0...2].joined(), buildParts[1] == parts[3],
              let round = Int(buildParts[2]), round > 0 else { return version }
        return "\(version) · Beta 构建 \(round)"
    }
}
