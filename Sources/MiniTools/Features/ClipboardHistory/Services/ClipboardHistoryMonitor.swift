import AppKit

@MainActor
final class ClipboardHistoryMonitor {
    var onCapture: ((ClipboardHistoryCapture) async -> Void)?
    var onRecognizedText: ((UUID, String, String) async -> Void)?
    var onError: ((String) -> Void)?

    private let pasteboard: NSPasteboard
    private let process: @Sendable (ClipboardHistoryCaptureService.Snapshot) -> ClipboardHistoryCapture?
    private let recognize: @Sendable (Data) throws -> String?
    private var timer: Timer?
    private var lastChangeCount: Int
    private var isEnabled = false
    private var generation = 0
    private var captureTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?

    init(pasteboard: NSPasteboard = .general,
         process: @escaping @Sendable (ClipboardHistoryCaptureService.Snapshot) -> ClipboardHistoryCapture? = ClipboardHistoryCaptureService.process,
         recognize: @escaping @Sendable (Data) throws -> String? = {
             try ImageRecognitionService.recognizeContents(in: $0).recognizedText
         }) {
        self.pasteboard = pasteboard
        self.process = process
        self.recognize = recognize
        lastChangeCount = pasteboard.changeCount
    }

    func start(enabled: Bool) {
        isEnabled = enabled
        lastChangeCount = pasteboard.changeCount
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func setEnabled(_ enabled: Bool) {
        invalidateWork()
        isEnabled = enabled
        lastChangeCount = pasteboard.changeCount
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isEnabled = false
        invalidateWork()
    }

    private func invalidateWork() {
        generation += 1
        captureTask?.cancel()
        recognitionTask?.cancel()
        captureTask = nil
        recognitionTask = nil
    }

    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard isEnabled else { return }
        guard let snapshot = ResponsivenessMetrics.measure("ClipboardSnapshot", {
            ClipboardHistoryCaptureService.snapshot(from: pasteboard, sourceApplication: NSWorkspace.shared.frontmostApplication)
        }), pasteboard.changeCount == changeCount else { return }
        let previous = captureTask
        let generation = generation
        let process = process
        captureTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.generation == generation, isEnabled else { return }
            let capture = await Task.detached(priority: .utility) {
                ResponsivenessMetrics.measure("ClipboardProcessing") { process(snapshot) }
            }.value
            guard !Task.isCancelled, self.generation == generation, isEnabled, let capture else { return }
            // Await persistence before OCR can update the record; preserve copy order.
            await onCapture?(capture)
            guard self.generation == generation, isEnabled else { return }
            if let image = snapshot.imageData { enqueueRecognition(image, capture: capture, generation: generation) }
        }
    }

    private func enqueueRecognition(_ image: Data, capture: ClipboardHistoryCapture, generation: Int) {
        let previous = recognitionTask
        let recognize = recognize
        recognitionTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.generation == generation, isEnabled else { return }
            let text = await Task.detached(priority: .utility) { try? ResponsivenessMetrics.measure("ClipboardOCR") { try recognize(image) } }.value
            guard !Task.isCancelled, self.generation == generation, isEnabled,
                  let text, !text.isEmpty else { return }
            await onRecognizedText?(capture.item.id, capture.item.contentHash, text)
        }
    }
}
