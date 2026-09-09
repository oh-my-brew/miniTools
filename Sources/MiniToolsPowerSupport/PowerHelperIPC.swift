import Foundation
import Security

public enum PowerHelperIPC {
    public static let machServiceName = "com.omzcj.minitools.power-helper"
    public static let plistName = "com.omzcj.minitools.power-helper.plist"
    public static let appCodeSignIdentifier = "com.omzcj.minitools"
    public static let helperCodeSignIdentifier = "com.omzcj.minitools.power-helper"
    public static let protocolVersion = 1

    public static func peerRequirement(identifier: String) -> String {
        guard let teamIdentifier = selfTeamIdentifier() else {
            return "identifier \"\(identifier)\""
        }
        return "anchor apple generic and identifier \"\(identifier)\""
            + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    private static func selfTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let dictionary = information as? [String: Any] else {
            return nil
        }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

public enum PowerHelperResult: Int32, Sendable {
    case success = 0
    case commandFailed = 1
}

@objc public protocol PowerHelperProtocol {
    func ping(reply: @escaping @Sendable (Int) -> Void)
    func setSleepDisabled(
        _ disabled: Bool,
        reply: @escaping @Sendable (Int32) -> Void
    )
    func currentState(
        reply: @escaping @Sendable (Int32, Bool) -> Void
    )
}

public struct PowerCommandResult: Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public enum PowerSettingsParser {
    public static func sleepDisabled(from output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard tokens.count >= 2, tokens[0] == "SleepDisabled" else { continue }
            switch tokens[1] {
            case "0": return false
            case "1": return true
            default: return nil
            }
        }
        // Some macOS releases omit SleepDisabled entirely while it is at the
        // default value. A successful `pmset -g` with no key therefore means
        // sleep is enabled, rather than an unreadable state.
        return false
    }
}

public enum PowerCommandRunner {
    public static func setSleepDisabled(_ disabled: Bool) -> PowerCommandResult {
        run(arguments: ["-a", "disablesleep", disabled ? "1" : "0"])
    }

    public static func currentSettings() -> PowerCommandResult {
        run(arguments: ["-g"])
    }

    private static func run(arguments: [String]) -> PowerCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return PowerCommandResult(exitCode: -1, output: error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return PowerCommandResult(
            exitCode: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}
