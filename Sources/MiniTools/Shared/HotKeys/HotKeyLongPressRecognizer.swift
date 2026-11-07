import Foundation

@MainActor
final class HotKeyLongPressRecognizer {
    static let defaultThresholdMilliseconds = 200
    static let minimumThresholdMilliseconds = 100
    static let maximumThresholdMilliseconds = 600
    static let thresholdStepMilliseconds = 25
    static let defaultThreshold: Duration = .milliseconds(defaultThresholdMilliseconds)
    typealias Schedule = (Duration, @escaping @MainActor () -> Void) -> (() -> Void)

    private var threshold: Duration
    private let schedule: Schedule
    private let onShortPress: () -> Void
    private let onLongPress: () -> Void
    private var cancelScheduled: (() -> Void)?
    private var isPressed = false
    private var didTriggerLongPress = false
    private var generation: UInt64 = 0

    init(threshold: Duration = defaultThreshold,
         schedule: @escaping Schedule = { delay, fire in
             let task = Task { @MainActor in
                 try? await Task.sleep(for: delay)
                 guard !Task.isCancelled else { return }
                 fire()
             }
             return { task.cancel() }
         },
         onShortPress: @escaping () -> Void,
         onLongPress: @escaping () -> Void) {
        self.threshold = threshold
        self.schedule = schedule
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
        generation &+= 1
        let ticket = generation
        cancelScheduled = schedule(threshold) { [weak self] in
            guard let self, self.generation == ticket, self.isPressed,
                  !self.didTriggerLongPress else { return }
            self.didTriggerLongPress = true
            self.onLongPress()
        }
    }

    func release() {
        guard isPressed else { return }
        let shouldTriggerShort = !didTriggerLongPress
        cancel()
        if shouldTriggerShort { onShortPress() }
    }

    func cancel() {
        generation &+= 1
        cancelScheduled?()
        cancelScheduled = nil
        isPressed = false
        didTriggerLongPress = false
    }
}
