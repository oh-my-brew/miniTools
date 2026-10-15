import Foundation

@MainActor
final class HotKeyLongPressRecognizer {
    static let defaultThresholdMilliseconds = 200
    static let minimumThresholdMilliseconds = 100
    static let maximumThresholdMilliseconds = 600
    static let thresholdStepMilliseconds = 25
    static let defaultThreshold: Duration = .milliseconds(defaultThresholdMilliseconds)

    private var threshold: Duration
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

    static func normalizedThresholdMilliseconds(_ value: Int) -> Int {
        min(max(value, minimumThresholdMilliseconds), maximumThresholdMilliseconds)
    }

    func updateThreshold(_ threshold: Duration) {
        cancel()
        self.threshold = threshold
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
