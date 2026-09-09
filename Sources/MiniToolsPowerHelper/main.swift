import Darwin
import Foundation
import MiniToolsPowerSupport

private final class PowerService: NSObject, PowerHelperProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.omzcj.minitools.power-helper")

    func ping(reply: @escaping @Sendable (Int) -> Void) {
        reply(PowerHelperIPC.protocolVersion)
    }

    func setSleepDisabled(
        _ disabled: Bool,
        reply: @escaping @Sendable (Int32) -> Void
    ) {
        queue.async {
            let result = PowerCommandRunner.setSleepDisabled(disabled)
            reply(
                result.exitCode == 0
                    ? PowerHelperResult.success.rawValue
                    : PowerHelperResult.commandFailed.rawValue
            )
        }
    }

    func currentState(
        reply: @escaping @Sendable (Int32, Bool) -> Void
    ) {
        queue.async {
            let settings = PowerCommandRunner.currentSettings()
            guard settings.exitCode == 0,
                  let disabled = PowerSettingsParser.sleepDisabled(from: settings.output) else {
                reply(PowerHelperResult.commandFailed.rawValue, false)
                return
            }
            reply(PowerHelperResult.success.rawValue, disabled)
        }
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let service = PowerService()
    private let queue = DispatchQueue(label: "com.omzcj.minitools.power-helper.connections")
    private var connections = Set<ObjectIdentifier>()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.setCodeSigningRequirement(
            PowerHelperIPC.peerRequirement(identifier: PowerHelperIPC.appCodeSignIdentifier)
        )
        connection.exportedInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        connection.exportedObject = service

        let identifier = ObjectIdentifier(connection)
        queue.sync {
            _ = connections.insert(identifier)
        }
        connection.invalidationHandler = { [weak self] in
            self?.connectionEnded(identifier)
        }
        connection.resume()
        return true
    }

    private func connectionEnded(_ identifier: ObjectIdentifier) {
        queue.async { [weak self] in
            guard let self else { return }
            connections.remove(identifier)
            if connections.isEmpty {
                exit(EXIT_SUCCESS)
            }
        }
    }
}

private func runPowerHelper() -> Never {
    let delegate = ListenerDelegate()
    let listener = NSXPCListener(machServiceName: PowerHelperIPC.machServiceName)
    listener.delegate = delegate
    listener.resume()
    dispatchMain()
}

runPowerHelper()
