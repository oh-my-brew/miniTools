import AppKit
import Foundation
import MiniToolsPowerSupport
import ServiceManagement

enum ClosedLidHelperState: Equatable {
    case unavailable, notEnabled, awaitingApproval, enabled, missing

    var title: String {
        switch self {
        case .unavailable: "请从“应用程序”运行"
        case .notEnabled: "未启用"
        case .awaitingApproval: "等待批准"
        case .enabled: "已启用"
        case .missing: "组件缺失"
        }
    }
}

enum ClosedLidBatteryPolicy {
    static let disableBelowPercent = 20
    static let enableAbovePercent = 25
    static let monitoringInterval: Duration = .seconds(60)

    static func targetSleepDisabled(batteryPercent: Int) -> Bool? {
        if batteryPercent < disableBelowPercent { return false }
        if batteryPercent > enableAbovePercent { return true }
        return nil
    }
}

@MainActor
final class ClosedLidRunningController: ObservableObject {
    @Published private(set) var isFeatureEnabled: Bool
    @Published private(set) var actualSleepDisabled: Bool?
    @Published private(set) var isBusy = false
    @Published private(set) var helperState: ClosedLidHelperState = .unavailable
    @Published private(set) var lastError: String?

    var onStateChanged: (() -> Void)?

    var actualStateTitle: String {
        switch actualSleepDisabled {
        case true: "1（阻止睡眠）"
        case false: "0（允许睡眠）"
        case nil: "未知"
        }
    }

    private let settings: AppSettings
    private let client: PowerHelperClient
    private let service: SMAppService
    private var monitorTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var approvalTask: Task<Void, Never>?

    init(
        settings: AppSettings,
        client: PowerHelperClient = PowerHelperClient()
    ) {
        self.settings = settings
        self.client = client
        isFeatureEnabled = settings.closedLidRunningEnabled
        actualSleepDisabled = nil
        service = SMAppService.daemon(plistName: PowerHelperIPC.plistName)
    }

    func start() {
        refreshHelperState()
        guard helperState == .enabled else { return }
        startMonitoring()
        reconcileActualState()
    }

    func stop() {
        monitorTask?.cancel()
        operationTask?.cancel()
        approvalTask?.cancel()
        monitorTask = nil
        operationTask = nil
        approvalTask = nil
        client.invalidate()
    }

    func refresh() {
        refreshHelperState()
        guard helperState == .enabled else {
            actualSleepDisabled = nil
            notifyStateChanged()
            return
        }
        startMonitoring()
        if !isBusy { reconcileActualState() }
    }

    func enable() {
        guard !isBusy, !isFeatureEnabled else { return }
        isFeatureEnabled = true
        settings.updateClosedLidRunningEnabled(true)
        if helperState == .enabled {
            startMonitoring()
            reconcileActualState()
        } else {
            enableHelper()
        }
        notifyStateChanged()
    }

    func disable() {
        guard !isBusy, isFeatureEnabled else { return }
        isFeatureEnabled = false
        settings.updateClosedLidRunningEnabled(false)
        if helperState == .enabled {
            applySleepDisabled(false, failureMessage: "无法关闭合盖运行")
        } else {
            notifyStateChanged()
        }
    }

    func enableHelper() {
        guard managesHelper else {
            helperState = .unavailable
            notifyStateChanged()
            return
        }
        lastError = nil
        do { try service.register() } catch {
            // A pending approval is reported through service.status below.
        }
        refreshHelperState()
        switch helperState {
        case .awaitingApproval:
            SMAppService.openSystemSettingsLoginItems()
            pollForApproval()
        case .notEnabled:
            lastError = "后台服务未能注册"
        case .enabled:
            startMonitoring()
            reconcileActualState()
        default:
            break
        }
        notifyStateChanged()
    }

    func openHelperApproval() {
        SMAppService.openSystemSettingsLoginItems()
        pollForApproval()
    }

    private func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: ClosedLidBatteryPolicy.monitoringInterval)
                guard let self, !Task.isCancelled, !isBusy else { continue }
                reconcileActualState()
            }
        }
    }

    private func reconcileActualState() {
        guard helperState == .enabled, operationTask == nil else { return }
        isBusy = true
        let client = client
        operationTask = Task { [weak self] in
            let result = await Task.detached { client.currentState() }.value
            guard let self, !Task.isCancelled else { return }
            operationTask = nil
            isBusy = false
            guard result.0 == .success else {
                actualSleepDisabled = nil
                lastError = "无法读取 SleepDisabled 实际值"
                client.invalidate()
                notifyStateChanged()
                return
            }

            actualSleepDisabled = result.1
            lastError = nil
            guard isFeatureEnabled,
                  let batteryPercent = ClosedLidSafetyMonitor.snapshot().batteryPercent,
                  let target = ClosedLidBatteryPolicy.targetSleepDisabled(
                      batteryPercent: batteryPercent
                  ),
                  target != result.1 else {
                notifyStateChanged()
                return
            }
            applySleepDisabled(
                target,
                failureMessage: target
                    ? "无法按当前电量开启合盖运行"
                    : "无法按当前电量关闭合盖运行"
            )
        }
    }

    private func applySleepDisabled(_ disabled: Bool, failureMessage: String) {
        guard operationTask == nil else { return }
        isBusy = true
        notifyStateChanged()
        let client = client
        operationTask = Task { [weak self] in
            let result = await Task.detached {
                client.setSleepDisabled(disabled)
            }.value
            guard let self, !Task.isCancelled else { return }
            operationTask = nil
            isBusy = false
            if result == .success {
                actualSleepDisabled = disabled
                lastError = nil
            } else {
                actualSleepDisabled = nil
                lastError = failureMessage
                client.invalidate()
            }
            notifyStateChanged()
        }
    }

    private func refreshHelperState() {
        guard managesHelper else {
            helperState = .unavailable
            return
        }
        helperState = switch service.status {
        case .notRegistered: .notEnabled
        case .enabled: .enabled
        case .requiresApproval: .awaitingApproval
        case .notFound: .missing
        @unknown default: .missing
        }
    }

    private func pollForApproval() {
        approvalTask?.cancel()
        approvalTask = Task { [weak self] in
            for _ in 0..<150 {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                refreshHelperState()
                notifyStateChanged()
                if helperState != .awaitingApproval {
                    if helperState == .enabled {
                        startMonitoring()
                        reconcileActualState()
                    }
                    return
                }
            }
        }
    }

    private var managesHelper: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    private func notifyStateChanged() { onStateChanged?() }
}
