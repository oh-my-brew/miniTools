import AppKit

@MainActor
final class ClipboardHistoryMonitor {
    var onCapture: ((ClipboardHistoryCapture) -> Void)?
    var onError: ((String) -> Void)?

    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int
    private var isEnabled = false

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
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
        isEnabled = enabled
        lastChangeCount = pasteboard.changeCount
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard isEnabled else { return }

        let sourceApplication = NSWorkspace.shared.frontmostApplication
        guard var capture = ClipboardHistoryCaptureService.capture(
            from: pasteboard,
            sourceApplication: sourceApplication
        ) else { return }

        let imageData = capture.payloads.first(where: {
            $0.typeIdentifier.hasPrefix("public.")
                && ($0.typeIdentifier.contains("png")
                    || $0.typeIdentifier.contains("jpeg")
                    || $0.typeIdentifier.contains("tiff")
                    || $0.typeIdentifier.contains("heic"))
        })?.data

        guard let imageData else {
            onCapture?(capture)
            return
        }

        onCapture?(capture)

        Task.detached(priority: .utility) { [weak self] in
            let recognizedText = try? ImageRecognitionService
                .recognizeContents(in: imageData).recognizedText
            guard let recognizedText, !recognizedText.isEmpty else { return }
            capture.item.searchableText += "\n" + recognizedText
            await MainActor.run {
                self?.onCapture?(capture)
            }
        }
    }
}
