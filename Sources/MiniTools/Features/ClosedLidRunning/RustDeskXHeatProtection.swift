import AppKit
import Foundation
import IOKit
import IOKit.pwr_mgt

// IOPM.h exposes this public message as a C expression that Swift cannot import.
enum RustDeskXClamshellEvent {
    static let stateChangeMessage: natural_t = 0xe003_4100

    static func indicatesClosed(messageType: natural_t, argument: UInt) -> Bool {
        messageType == stateChangeMessage && argument & UInt(kClamshellStateBit) != 0
    }
}

enum RustDeskXProtectionTrigger: Equatable {
    case lidClosed
    case sessionLocked

    var title: String {
        switch self {
        case .lidClosed: "合盖"
        case .sessionLocked: "锁屏"
        }
    }
}

protocol RustDeskXProcessTerminating {
    func forceTerminateRunningInstances() -> RustDeskXTerminationResult
}

struct RustDeskXTerminationResult: Equatable {
    let runningCount: Int
    let terminatedCount: Int
}

struct WorkspaceRustDeskXProcessTerminator: RustDeskXProcessTerminating {
    static let bundleIdentifier = "com.omzcj.rustdeskx"

    func forceTerminateRunningInstances() -> RustDeskXTerminationResult {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        )
        let terminatedCount = applications.reduce(into: 0) { count, application in
            if application.forceTerminate() {
                count += 1
            }
        }
        return RustDeskXTerminationResult(
            runningCount: applications.count,
            terminatedCount: terminatedCount
        )
    }
}

@MainActor
protocol RustDeskXProtectionEventMonitoring: AnyObject {
    var onTrigger: ((RustDeskXProtectionTrigger) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class SystemRustDeskXProtectionEventMonitor: RustDeskXProtectionEventMonitoring {
    var onTrigger: ((RustDeskXProtectionTrigger) -> Void)?

    private let workspaceNotificationCenter: NotificationCenter
    private var sessionObserver: NSObjectProtocol?
    private var notificationPort: IONotificationPortRef?
    private var rootDomain: io_service_t = 0
    private var notifier: io_object_t = 0

    init(workspace: NSWorkspace = .shared) {
        workspaceNotificationCenter = workspace.notificationCenter
    }

    func start() {
        guard sessionObserver == nil else { return }
        sessionObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onTrigger?(.sessionLocked)
            }
        }
        startClamshellMonitoring()
    }

    func stop() {
        if let sessionObserver {
            workspaceNotificationCenter.removeObserver(sessionObserver)
            self.sessionObserver = nil
        }
        if notifier != 0 {
            IOObjectRelease(notifier)
            notifier = 0
        }
        if rootDomain != 0 {
            IOObjectRelease(rootDomain)
            rootDomain = 0
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
    }

    private func startClamshellMonitoring() {
        guard notificationPort == nil else { return }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else {
            if service != 0 { IOObjectRelease(service) }
            return
        }

        rootDomain = service
        notificationPort = port
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        let status = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            { reference, _, messageType, messageArgument in
                guard let reference, let messageArgument else { return }
                let state = UInt(bitPattern: messageArgument)
                guard RustDeskXClamshellEvent.indicatesClosed(
                    messageType: messageType,
                    argument: state
                ) else { return }
                let monitor = Unmanaged<SystemRustDeskXProtectionEventMonitor>
                    .fromOpaque(reference).takeUnretainedValue()
                MainActor.assumeIsolated {
                    monitor.onTrigger?(.lidClosed)
                }
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &notifier
        )
        if status != KERN_SUCCESS {
            stop()
            return
        }
        if currentClamshellState() == true {
            onTrigger?(.lidClosed)
        }
    }

    private func currentClamshellState() -> Bool? {
        guard rootDomain != 0,
              let value = IORegistryEntryCreateCFProperty(
                  rootDomain,
                  kAppleClamshellStateKey as CFString,
                  kCFAllocatorDefault,
                  0
              )?.takeRetainedValue() else { return nil }
        return value as? Bool
    }

    deinit {
        MainActor.assumeIsolated { stop() }
    }
}

@MainActor
final class RustDeskXHeatProtectionController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastAction: String?
    @Published private(set) var lastError: String?

    private let settings: AppSettings
    private let monitor: any RustDeskXProtectionEventMonitoring
    private let terminator: any RustDeskXProcessTerminating

    init(
        settings: AppSettings,
        monitor: any RustDeskXProtectionEventMonitoring = SystemRustDeskXProtectionEventMonitor(),
        terminator: any RustDeskXProcessTerminating = WorkspaceRustDeskXProcessTerminator()
    ) {
        self.settings = settings
        self.monitor = monitor
        self.terminator = terminator
        isEnabled = settings.rustDeskXHeatProtectionEnabled
        monitor.onTrigger = { [weak self] trigger in
            self?.handle(trigger)
        }
    }

    func start() {
        if isEnabled { monitor.start() }
    }

    func stop() {
        monitor.stop()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        settings.updateRustDeskXHeatProtectionEnabled(enabled)
        lastAction = nil
        lastError = nil
        if enabled {
            monitor.start()
        } else {
            monitor.stop()
        }
    }

    private func handle(_ trigger: RustDeskXProtectionTrigger) {
        guard isEnabled else { return }
        let result = terminator.forceTerminateRunningInstances()
        if result.terminatedCount > 0 {
            lastAction = "已在\(trigger.title)时强制关闭 RustDeskX"
        }
        if result.runningCount > result.terminatedCount {
            lastError = "\(trigger.title)时无法强制关闭 RustDeskX"
        } else {
            lastError = nil
        }
    }
}
