import Foundation

@MainActor
final class ApplicationContext: ObservableObject {
    let settings: AppSettings
    let usageStatistics: UsageStatisticsStore
    @Published private(set) var shortcutCoordinator: GlobalShortcutCoordinator?
    @Published private(set) var mouseBindingCoordinator: MouseBindingCoordinator?
    @Published private(set) var closedLidRunningController: ClosedLidRunningController?
    @Published private(set) var dsStoreManagementController: DSStoreManagementController?

    init(
        settings: AppSettings = AppSettings(),
        usageStatistics: UsageStatisticsStore = UsageStatisticsStore()
    ) {
        self.settings = settings
        self.usageStatistics = usageStatistics
    }

    func install(shortcutCoordinator: GlobalShortcutCoordinator) {
        self.shortcutCoordinator = shortcutCoordinator
    }

    func install(mouseBindingCoordinator: MouseBindingCoordinator) {
        self.mouseBindingCoordinator = mouseBindingCoordinator
    }

    func install(closedLidRunningController: ClosedLidRunningController) {
        self.closedLidRunningController = closedLidRunningController
    }

    func install(dsStoreManagementController: DSStoreManagementController) {
        self.dsStoreManagementController = dsStoreManagementController
    }
}
