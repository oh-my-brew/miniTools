import AppKit

@MainActor
final class WindowControlController {
    private let settings: AppSettings
    private let usageStatistics: UsageStatisticsStore
    private let cursorHighlightController = CursorHighlightController()
    private let feedbackController = WindowActionFeedbackController()

    init(settings: AppSettings, usageStatistics: UsageStatisticsStore) {
        self.settings = settings
        self.usageStatistics = usageStatistics
    }

    func perform(
        _ id: WindowControlID,
        cursorHighlightStyles: Set<CursorHighlightStyle>
    ) {
        let usesSystemWindowActions = settings.usesSystemWindowActions
        if let command = WindowControlCatalog.layoutCommand(for: id) {
            performWindowAction(id: id) {
                try await WindowLayoutService.applyLayout(
                    command,
                    usesSystemWindowActions: usesSystemWindowActions
                )
            }
            return
        }

        switch id {
        case .moveWindowToNextScreen:
            performWindowAction(id: id) {
                try await WindowLayoutService.moveFocusedWindowToNextScreen(
                    usesSystemWindowActions: usesSystemWindowActions
                )
            }
        case .movePointerToNextScreen:
            movePointerToNextScreen(cursorHighlightStyles: cursorHighlightStyles)
        case .centerWindow:
            performWindowAction(id: id) {
                try await WindowLayoutService.centerFocusedWindow(
                    usesSystemWindowActions: usesSystemWindowActions
                )
            }
        default:
            break
        }
    }

    private func movePointerToNextScreen(
        cursorHighlightStyles: Set<CursorHighlightStyle>
    ) {
        Task { [weak self] in
            do {
                let target = try await PointerMover.moveToNextScreen()
                self?.cursorHighlightController.show(
                    atAccessibilityPoint: target,
                    enabledStyles: cursorHighlightStyles
                )
                self?.usageStatistics.record(
                    id: WindowControlID.movePointerToNextScreen.rawValue,
                    title: "鼠标移至下一屏",
                    category: .mouseCrossScreen
                )
            } catch {
                self?.report(error)
            }
        }
    }

    private func performWindowAction(
        id: WindowControlID,
        _ action: @escaping () async throws -> WindowActionOutcome
    ) {
        Task { [weak self] in
            do {
                let outcome = try await action()
                guard let self else { return }
                let title = WindowControlCatalog.targetTitle(
                    for: id,
                    candidateIndex: outcome.candidateIndex
                )
                usageStatistics.record(
                    id: WindowControlCatalog.statisticsID(
                        for: id,
                        candidateIndex: outcome.candidateIndex
                    ),
                    title: title,
                    category: .windowManagement
                )
                // 只有真正调用到 macOS 原生能力时才提示来源。
                if outcome.implementation == .macOSNative {
                    feedbackController.showNativeAction(title: title)
                }
            } catch {
                self?.report(error)
            }
        }
    }

    private func report(_ error: Error) {
        NSSound.beep()
        let message = error.localizedDescription
        feedbackController.showError(message)
    }
}
