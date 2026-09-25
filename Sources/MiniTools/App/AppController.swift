import AppKit

@MainActor
final class AppController: NSObject {
    private let applicationContext: ApplicationContext
    private var settings: AppSettings { applicationContext.settings }
    private let statusMenuController = StatusMenuController()
    private lazy var windowControlController = WindowControlController(settings: settings)
    private lazy var closedLidRunningController = ClosedLidRunningController(
        settings: settings
    )
    private lazy var dsStoreManagementController = DSStoreManagementController(
        settings: settings
    )
    private let featurePanelController: FeaturePanelController
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
            settings: applicationContext.settings
        )
        super.init()
    }

    func start() {
        shortcutCoordinator = GlobalShortcutCoordinator(
            settings: settings,
            showPanel: { [weak self] in
                self?.commandDispatcher.perform(.toggleLastFeaturePanel)
            },
            performWindowControl: { [weak self] id in
                self?.commandDispatcher.perform(.windowControl(id))
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
        applicationContext.install(dsStoreManagementController: dsStoreManagementController)

        settingsWindowController = SettingsWindowController(
            settings: settings,
            shortcutCoordinator: shortcutCoordinator,
            mouseBindingCoordinator: mouseBindingCoordinator,
            closedLidRunningController: closedLidRunningController,
            dsStoreManagementController: dsStoreManagementController,
            previewCursorHighlight: applicationContext.previewCursorHighlight
        )
        featurePanelController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }

        statusMenuController.onOpenPanel = { [weak self] in
            self?.featurePanelController.toggleLastUsedPanel()
        }
        statusMenuController.onOpenSettings = { [weak self] in
            self?.showSettings()
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
        dsStoreManagementController.start()
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
        settingsWindowController?.show()
    }

    func stop() {
        featurePanelPreparationTask?.cancel()
        featurePanelPreparationTask = nil
        mouseBindingCoordinator?.stop()
        closedLidRunningController.stop()
        dsStoreManagementController.stop()
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
