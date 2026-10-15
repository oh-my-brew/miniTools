import Foundation

@MainActor
final class HotKeyLongPressRecognizer {
    static let defaultThreshold: Duration = .milliseconds(400)

    private let threshold: Duration
    private let onShortPress: () -> Void
    private let onLongPress: () -> Void
    private var holdTask: Task<Void, Never>?
    private var isPressed = false
    private var didTriggerLongPress = false

    init(
        threshold: Duration = defaultThreshold,
        onShortPress: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) {
        self.threshold = threshold
        self.onShortPress = onShortPress
        self.onLongPress = onLongPress
    }

    func press() {
        guard !isPressed else { return }
        isPressed = true
        didTriggerLongPress = false
        holdTask?.cancel()
        holdTask = Task { @MainActor [weak self, threshold] in
            try? await Task.sleep(for: threshold)
            guard !Task.isCancelled, let self, self.isPressed else { return }
            self.didTriggerLongPress = true
            self.onLongPress()
        }
    }

    func release() {
        guard isPressed else { return }
        isPressed = false
        holdTask?.cancel()
        holdTask = nil
        if !didTriggerLongPress {
            onShortPress()
        }
        didTriggerLongPress = false
    }

    func cancel() {
        holdTask?.cancel()
        holdTask = nil
        isPressed = false
        didTriggerLongPress = false
    }
}
