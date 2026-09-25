import AppKit
import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case unavailable, disabled, enabled, requiresApproval, failed

    var title: String {
        switch self {
        case .unavailable: "请从“应用程序”运行"
        case .disabled: "未启用"
        case .enabled: "已启用"
        case .requiresApproval: "等待批准"
        case .failed: "状态异常"
        }
    }
}

@MainActor
final class DSStoreManagementController: ObservableObject {
    @Published private(set) var deletedCount = 0
    @Published private(set) var lastError: String?
    @Published private(set) var isCleaning = false
    @Published private(set) var isMonitoring = false
    @Published private(set) var loginItemState: LoginItemState = .unavailable

    private let settings: AppSettings
    private let monitor: DSStoreEventMonitor
    private var cleanupTask: Task<Void, Never>?

    init(
        settings: AppSettings,
        monitor: DSStoreEventMonitor = DSStoreEventMonitor()
    ) {
        self.settings = settings
        self.monitor = monitor
        monitor.onDeleted = { [weak self] in
            Task { @MainActor in self?.deletedCount += 1 }
        }
        monitor.onError = { [weak self] message in
            Task { @MainActor in self?.lastError = message }
        }
    }

    func start() {
        refreshLoginItemState()
        reconcileMonitoring()
    }

    func stop() {
        cleanupTask?.cancel()
        cleanupTask = nil
        monitor.stop()
        isMonitoring = false
    }

    func setFeatureEnabled(_ enabled: Bool) {
        settings.updateDSStoreManagementEnabled(enabled)
        reconcileMonitoring()
    }

    func addDirectories(_ urls: [URL]) {
        let accepted = urls.compactMap(DSStorePathPolicy.normalizedSelectableDirectory)
        guard !accepted.isEmpty else {
            lastError = "请选择可读取的用户目录；不支持磁盘根目录、系统目录或应用包。"
            return
        }
        settings.updateDSStoreMonitoredDirectoryPaths(
            settings.dsStoreMonitoredDirectoryPaths + accepted.map(\.path)
        )
        lastError = nil
        reconcileMonitoring()
    }

    func removeDirectory(path: String) {
        settings.updateDSStoreMonitoredDirectoryPaths(
            settings.dsStoreMonitoredDirectoryPaths.filter { $0 != path }
        )
        reconcileMonitoring()
    }

    func cleanNow() {
        guard !isCleaning else { return }
        let directories = selectedDirectories
        guard !directories.isEmpty else {
            lastError = "请先选择要清理的目录。"
            return
        }
        isCleaning = true
        cleanupTask = Task { [weak self] in
            let result = await Task.detached {
                DSStoreCleaner.clean(directories: directories)
            }.value
            guard let self, !Task.isCancelled else { return }
            deletedCount += result.deletedCount
            if let error = result.lastError { lastError = error }
            isCleaning = false
            cleanupTask = nil
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard managesLoginItem else {
            settings.updateLaunchAtLoginEnabled(false)
            loginItemState = .unavailable
            return
        }
        lastError = nil
        do {
            if enabled {
                try loginItemService.register()
            } else {
                try loginItemService.unregister()
            }
            settings.updateLaunchAtLoginEnabled(enabled)
        } catch {
            lastError = "无法更新登录项：\(error.localizedDescription)"
        }
        refreshLoginItemState()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refreshLoginItemState() {
        guard managesLoginItem else {
            loginItemState = .unavailable
            return
        }
        loginItemState = switch loginItemService.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .failed
        @unknown default: .failed
        }
        let actualEnabled = loginItemState == .enabled || loginItemState == .requiresApproval
        if settings.launchAtLoginEnabled != actualEnabled {
            settings.updateLaunchAtLoginEnabled(actualEnabled)
        }
    }

    private func reconcileMonitoring() {
        monitor.stop()
        isMonitoring = false
        guard settings.dsStoreManagementEnabled else { return }
        let directories = selectedDirectories
        guard !directories.isEmpty else {
            lastError = "请先选择要监控的目录。"
            return
        }
        isMonitoring = monitor.start(directories: directories)
        if !isMonitoring {
            lastError = "无法启动所选目录的文件监控。"
        }
    }

    private var selectedDirectories: [URL] {
        settings.dsStoreMonitoredDirectoryPaths.map(URL.init(fileURLWithPath:))
    }

    private var managesLoginItem: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    private var loginItemService: SMAppService { .mainApp }
}
