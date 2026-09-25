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
        let title = WindowControlCatalog.descriptors.first(where: { $0.id == id })?.title
            ?? "窗口操作"
        if let command = WindowControlCatalog.layoutCommand(for: id) {
            performWindowAction(
                id: id,
                title: title,
                showsImplementationToast: usesSystemWindowActions
            ) {
                try await WindowLayoutService.applyLayout(
                    command,
                    usesSystemWindowActions: usesSystemWindowActions
                )
            }
            return
        }

        switch id {
        case .moveWindowToNextScreen:
            performWindowAction(
                id: id,
                title: title,
                showsImplementationToast: usesSystemWindowActions
            ) {
                try await WindowLayoutService.moveFocusedWindowToNextScreen(
                    usesSystemWindowActions: usesSystemWindowActions
                )
            }
        case .movePointerToNextScreen:
            movePointerToNextScreen(cursorHighlightStyles: cursorHighlightStyles)
        case .centerWindow:
            performWindowAction(
                id: id,
                title: title,
                showsImplementationToast: usesSystemWindowActions
            ) {
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
        title: String,
        showsImplementationToast: Bool,
        _ action: @escaping () async throws -> WindowActionImplementation
    ) {
        Task { [weak self] in
            do {
                let implementation = try await action()
                guard let self else { return }
                usageStatistics.record(
                    id: id.rawValue,
                    title: title,
                    category: .windowManagement
                )
                if showsImplementationToast {
                    feedbackController.showImplementation(
                        implementation,
                        actionTitle: title
                    )
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
