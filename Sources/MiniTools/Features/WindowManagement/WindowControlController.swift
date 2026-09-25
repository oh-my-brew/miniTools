import AppKit

@MainActor
final class WindowControlController {
    private let settings: AppSettings
    private let cursorHighlightController = CursorHighlightController()
    private let feedbackController = WindowActionFeedbackController()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func perform(
        _ id: WindowControlID,
        cursorHighlightStyles: Set<CursorHighlightStyle>
    ) {
        let usesSystemWindowActions = settings.usesSystemWindowActions
        if let command = WindowControlCatalog.layoutCommand(for: id) {
            performWindowAction {
                try await WindowLayoutService.applyLayout(
                    command,
                    usesSystemWindowActions: usesSystemWindowActions
                )
            }
            return
        }

        switch id {
        case .moveWindowToNextScreen:
            performWindowAction {
                try await WindowLayoutService.moveFocusedWindowToNextScreen(
                    usesSystemWindowActions: usesSystemWindowActions
                )
            }
        case .movePointerToNextScreen:
            movePointerToNextScreen(cursorHighlightStyles: cursorHighlightStyles)
        case .centerWindow:
            performWindowAction {
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
            } catch {
                self?.report(error)
            }
        }
    }

    private func performWindowAction(_ action: @escaping () async throws -> Void) {
        Task { [weak self] in
            do {
                try await action()
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
