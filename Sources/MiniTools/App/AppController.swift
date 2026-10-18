import AppKit

@MainActor
final class AppController: NSObject {
    private let applicationContext: ApplicationContext
    private var settings: AppSettings { applicationContext.settings }
    private let statusMenuController = StatusMenuController()
    private let appUpdateController = AppUpdateController()
    private lazy var windowControlController = WindowControlController(
        usageStatistics: applicationContext.usageStatistics
    )
    private lazy var closedLidRunningController = ClosedLidRunningController(
        settings: settings
    )
    private lazy var rustDeskXHeatProtectionController = RustDeskXHeatProtectionController(
        settings: settings
    )
    private lazy var dsStoreManagementController = DSStoreManagementController(
        settings: settings
    )
    private let featurePanelController: FeaturePanelController
    private let clipboardHistoryController: ClipboardHistoryPanelController
    private lazy var commandDispatcher = AppCommandDispatcher(
        settings: settings,
        featurePanelController: featurePanelController,
        windowControlController: windowControlController
    )

    private var shortcutCoordinator: GlobalShortcutCoordinator!
    private var mouseBindingCoordinator: MouseBindingCoordinator!
    private var settingsWindowController: SettingsWindowController?
    private var featurePanelPreparationTask: Task<Void, Never>?

    init(applicationContext: ApplicationContext) {
        self.applicationContext = applicationContext
        featurePanelController = FeaturePanelController(
            settings: applicationContext.settings,
            usageStatistics: applicationContext.usageStatistics
        )
        clipboardHistoryController = ClipboardHistoryPanelController(
            settings: applicationContext.settings
        )
        super.init()
    }

    func start() {
        shortcutCoordinator = GlobalShortcutCoordinator(
            settings: settings,
            showPanel: { [weak self] in
                self?.clipboardHistoryController.close(restoreFocus: false)
                self?.commandDispatcher.perform(.toggleLastFeaturePanel)
            },
            showClipboardHistory: { [weak self] in
                self?.featurePanelController.close(restoreFocus: false)
                self?.clipboardHistoryController.toggle()
            },
            performWindowControl: { [weak self] id in
                self?.commandDispatcher.perform(.windowControl(id))
            },
            performComposedWindowControl: { [weak self] id, press in
                self?.windowControlController.performComposed(id, press: press)
            }
        )
        mouseBindingCoordinator = MouseBindingCoordinator(
            settings: settings,
            performCommand: { [weak self] command in
                self?.commandDispatcher.perform(command)
            }
        )
        shortcutCoordinator.onStateChanged = { [weak self] in
            self?.updateStatusMenu()
        }
        closedLidRunningController.onStateChanged = { [weak self] in
            self?.updateStatusMenu()
        }
        applicationContext.install(shortcutCoordinator: shortcutCoordinator)
        applicationContext.install(mouseBindingCoordinator: mouseBindingCoordinator)
        applicationContext.install(closedLidRunningController: closedLidRunningController)
        applicationContext.install(
            rustDeskXHeatProtectionController: rustDeskXHeatProtectionController
        )
        applicationContext.install(dsStoreManagementController: dsStoreManagementController)
        applicationContext.install(clipboardHistoryController: clipboardHistoryController)

        settingsWindowController = SettingsWindowController(
            settings: settings,
            shortcutCoordinator: shortcutCoordinator,
            mouseBindingCoordinator: mouseBindingCoordinator,
            closedLidRunningController: closedLidRunningController,
            rustDeskXHeatProtectionController: rustDeskXHeatProtectionController,
            dsStoreManagementController: dsStoreManagementController,
            clipboardHistoryController: clipboardHistoryController,
            usageStatistics: applicationContext.usageStatistics
        )
        featurePanelController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        clipboardHistoryController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }

        statusMenuController.onOpenPanel = { [weak self] in
            self?.clipboardHistoryController.close(restoreFocus: false)
            self?.featurePanelController.toggleLastUsedPanel()
        }
        statusMenuController.onOpenClipboardHistory = { [weak self] in
            self?.featurePanelController.close(restoreFocus: false)
            self?.clipboardHistoryController.toggle()
        }
        statusMenuController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        statusMenuController.onCheckForUpdates = { [weak self] in
            self?.appUpdateController.checkForUpdates()
        }
        statusMenuController.onToggleClosedLidRunning = { [weak self] in
            guard let self else { return }
            if closedLidRunningController.isFeatureEnabled {
                closedLidRunningController.disable()
            } else {
                closedLidRunningController.enable()
            }
        }
        statusMenuController.onMenuWillOpen = { [weak self] in
            self?.closedLidRunningController.refresh()
            self?.updateStatusMenu()
        }
        statusMenuController.start()
        closedLidRunningController.start()
        rustDeskXHeatProtectionController.start()
        dsStoreManagementController.start()
        clipboardHistoryController.start()
        shortcutCoordinator.start()
        mouseBindingCoordinator.start()
        updateStatusMenu()

        // Constructing an NSHostingView while SwiftUI is still laying out the app's
        // Settings scene can re-enter AppKit layout. Prewarm on the next main-actor
        // turn so the first panel presentation is still ready without that overlap.
        featurePanelPreparationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.featurePanelController.prepare()
        }
    }

    @objc func showSettings() {
        featurePanelController.close(restoreFocus: false)
        clipboardHistoryController.close(restoreFocus: false)
        settingsWindowController?.show()
    }

    func stop() {
        featurePanelPreparationTask?.cancel()
        featurePanelPreparationTask = nil
        shortcutCoordinator?.stop()
        mouseBindingCoordinator?.stop()
        closedLidRunningController.stop()
        rustDeskXHeatProtectionController.stop()
        dsStoreManagementController.stop()
        clipboardHistoryController.stop()
        featurePanelController.stop()
    }

    private func updateStatusMenu() {
        guard shortcutCoordinator != nil else { return }
        statusMenuController.update(
            settings: settings,
            shortcutCoordinator: shortcutCoordinator,
            closedLidRunningController: closedLidRunningController
        )
    }
}
