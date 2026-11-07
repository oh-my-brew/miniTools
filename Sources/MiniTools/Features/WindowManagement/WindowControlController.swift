import AppKit

@MainActor
final class WindowControlController {
    private let usageStatistics: UsageStatisticsStore
    private let cursorHighlightController = CursorHighlightController()
    private let feedbackController = WindowActionFeedbackController()

    init(usageStatistics: UsageStatisticsStore) {
        self.usageStatistics = usageStatistics
    }

    func perform(
        _ id: WindowControlID,
        cursorHighlightStyles: Set<CursorHighlightStyle>,
        crossScreenPreservesLayout: Bool = false,
        compatibleApplications: Set<String> = WindowAdjustmentPolicy.defaultBundleIdentifiers
    ) {
        if let command = WindowControlCatalog.layoutCommand(for: id) {
            performWindowAction(id: id) {
                try await WindowLayoutService.applyLayout(command, compatibleApplications: compatibleApplications)
            }
            return
        }

        switch id {
        case .moveWindowToNextScreen:
            performWindowAction(id: id) {
                try await WindowLayoutService.moveFocusedWindowToNextScreen(
                    preservingLayout: crossScreenPreservesLayout, compatibleApplications: compatibleApplications
                )
            }
        case .movePointerToNextScreen:
            movePointerToNextScreen(cursorHighlightStyles: cursorHighlightStyles)
        case .centerWindow:
            performWindowAction(id: id) {
                try await WindowLayoutService.centerFocusedWindow(compatibleApplications: compatibleApplications)
            }
        default:
            break
        }
    }

    func performComposed(
        _ id: ComposedWindowControlID,
        press: WindowShortcutPress,
        compatibleApplications: Set<String>
    ) {
        Task { [weak self] in
            do {
                let outcome: WindowActionOutcome
                if let target = ComposedWindowControlCatalog.sizeTarget(for: id, press: press) {
                    outcome = try await WindowLayoutService.applyComposedSize(
                        target, compatibleApplications: compatibleApplications
                    )
                } else if let placement = ComposedWindowControlCatalog.placement(for: id) {
                    outcome = try await WindowLayoutService.applyComposedPlacement(
                        placement, compatibleApplications: compatibleApplications
                    )
                } else { return }
                guard let self, outcome.didReachTarget,
                      let statisticsID = outcome.statisticsID, let title = outcome.title else { return }
                usageStatistics.record(id: "composed.\(statisticsID)", title: title, category: .windowManagement)
            } catch is CancellationError {
                // Superseded operations must not display failure feedback.
            } catch {
                self?.report(error)
            }
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
                guard let self, outcome.didReachTarget else { return }
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
            } catch is CancellationError {
                // A newer explicit window command superseded this operation.
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
