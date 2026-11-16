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
        switch id {
        case .moveWindowToNextScreen:
            performWindowAction(id: id) {
                try await WindowLayoutService.moveFocusedWindowToNextScreen(
                    preservingLayout: crossScreenPreservesLayout, compatibleApplications: compatibleApplications
                )
            }
        case .movePointerToNextScreen:
            movePointerToNextScreen(cursorHighlightStyles: cursorHighlightStyles)
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
                let title = WindowControlCatalog.descriptors.first(where: { $0.id == id })?.title ?? id.rawValue
                usageStatistics.record(
                    id: id.rawValue,
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
