import AppKit

@MainActor
final class ClipboardHistoryMonitor {
    var onCapture: ((ClipboardHistoryCapture) async -> Void)?
    var onRecognizedText: ((UUID, String, String) async -> Void)?
    var onError: ((String) -> Void)?

    private let readChangeCount: () -> Int
    private let readSnapshot: () -> ClipboardHistoryCaptureService.ReadResult
    private let process: @Sendable (ClipboardHistoryCaptureService.Snapshot) -> ClipboardHistoryCapture?
    private let recognize: @Sendable (Data) throws -> String?
    private var timer: Timer?
    private var lastChangeCount: Int
    private var pendingChangeCount: Int?
    private var pendingAttempts = 0
    private var isEnabled = false
    private var generation = 0
    private var captureTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?

    convenience init(pasteboard: NSPasteboard = .general,
         process: @escaping @Sendable (ClipboardHistoryCaptureService.Snapshot) -> ClipboardHistoryCapture? = ClipboardHistoryCaptureService.process,
         recognize: @escaping @Sendable (Data) throws -> String? = {
             try ImageRecognitionService.recognizeContents(in: $0).recognizedText
         }) {
        self.init(readChangeCount: { pasteboard.changeCount }, readSnapshot: {
            ClipboardHistoryCaptureService.read(
                from: pasteboard, sourceApplication: NSWorkspace.shared.frontmostApplication
            )
        }, process: process, recognize: recognize)
    }

    init(readChangeCount: @escaping () -> Int,
         readSnapshot: @escaping () -> ClipboardHistoryCaptureService.ReadResult,
         process: @escaping @Sendable (ClipboardHistoryCaptureService.Snapshot) -> ClipboardHistoryCapture? = ClipboardHistoryCaptureService.process,
         recognize: @escaping @Sendable (Data) throws -> String? = {
             try ImageRecognitionService.recognizeContents(in: $0).recognizedText
         }) {
        self.readChangeCount = readChangeCount
        self.readSnapshot = readSnapshot
        self.process = process
        self.recognize = recognize
        lastChangeCount = readChangeCount()
    }

    func start(enabled: Bool) {
        isEnabled = enabled
        lastChangeCount = readChangeCount()
        pendingChangeCount = nil
        pendingAttempts = 0
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
        lastChangeCount = readChangeCount()
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
        pendingChangeCount = nil
        pendingAttempts = 0
    }

    func captureLatest() {
        let requestedGeneration = generation
        // Present the panel before touching a potentially slow pasteboard provider.
        Task { @MainActor [weak self] in
            guard let self, self.generation == requestedGeneration else { return }
            self.poll()
        }
    }

    func poll() {
        let changeCount = readChangeCount()
        guard changeCount != lastChangeCount else { return }
        guard isEnabled else { return }
        if pendingChangeCount != changeCount {
            pendingChangeCount = changeCount
            pendingAttempts = 0
        }
        pendingAttempts += 1
        let readingGeneration = generation
        let result = ResponsivenessMetrics.measure("ClipboardSnapshot", readSnapshot)
        guard isEnabled, generation == readingGeneration else { return }
        // Never combine data from different copies. A new count is read on the next poll.
        guard readChangeCount() == changeCount else { return }
        let snapshot: ClipboardHistoryCaptureService.Snapshot
        switch result {
        case let .captured(value):
            snapshot = value
        case .ignored:
            lastChangeCount = changeCount
            return
        case .unavailable:
            // Promised data may become readable without another changeCount.
            // Retry on the existing timer, with a maximum of three reads per copy.
            if pendingAttempts >= 3 {
                lastChangeCount = changeCount
                onError?("未能读取本次复制内容，未加入剪贴板历史")
            }
            return
        }
        lastChangeCount = changeCount
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
