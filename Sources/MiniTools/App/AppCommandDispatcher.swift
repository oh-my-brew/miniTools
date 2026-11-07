import Foundation

@MainActor
final class AppCommandDispatcher {
    private let settings: AppSettings
    private let featurePanelController: FeaturePanelController
    private let windowControlController: WindowControlController

    init(
        settings: AppSettings,
        featurePanelController: FeaturePanelController,
        windowControlController: WindowControlController
    ) {
        self.settings = settings
        self.featurePanelController = featurePanelController
        self.windowControlController = windowControlController
    }

    func perform(_ command: AppCommand) {
        switch command {
        case .toggleLastFeaturePanel:
            featurePanelController.toggleLastUsedPanel()
        case let .showFeaturePanel(panel):
            featurePanelController.show(panel)
        case let .windowControl(control):
            windowControlController.perform(
                control,
                cursorHighlightStyles: settings.cursorHighlightStyles,
                crossScreenPreservesLayout: settings.crossScreenPreservesLayout,
                compatibleApplications: settings.windowCompatibilityApplications
            )
        }
    }
}
