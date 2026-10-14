import AppKit

@MainActor
final class WindowActionFeedbackController {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func showError(_ message: String) {
        show(message, duration: 1.35)
    }

    private func show(_ message: String, duration: TimeInterval) {
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        let fittingWidth = ceil(label.intrinsicContentSize.width) + 54
        let size = CGSize(width: min(max(fittingWidth, 240), 520), height: 48)
        let effectView = NSGlassEffectView(frame: CGRect(origin: .zero, size: size))
        effectView.style = .regular
        effectView.cornerRadius = 12

        let contentView = NSView(frame: effectView.bounds)
        label.frame = contentView.bounds.insetBy(dx: 18, dy: 12)
        contentView.addSubview(label)
        effectView.contentView = contentView

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let frame = CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 90,
            width: size.width,
            height: size.height
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effectView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let panel else { return }
            if self?.panel === panel { self?.panel = nil }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }
            let closeWorkItem = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: closeWorkItem)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}
