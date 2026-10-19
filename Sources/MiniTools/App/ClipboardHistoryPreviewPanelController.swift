import AppKit
import QuickLookUI

@MainActor
final class ClipboardHistoryPreviewPanelController {
    private let panel: NSPanel
    private let previewView: QLPreviewView
    private let titleField = NSTextField(labelWithString: "")
    private let sourceField = NSTextField(labelWithString: "")
    private let container = NSVisualEffectView()
    private var previewSize = CGSize.zero

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        previewView = QLPreviewView(frame: .zero, style: .compact)

        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        sourceField.font = .systemFont(ofSize: 12)
        sourceField.textColor = .secondaryLabelColor
        sourceField.alignment = .right
        sourceField.lineBreakMode = .byTruncatingTail

        previewView.shouldCloseWithWindow = true
        previewView.autostarts = false
        container.addSubview(previewView)
        container.addSubview(titleField)
        container.addSubview(sourceField)
        panel.contentView = container
    }

    var isVisible: Bool { panel.isVisible }

    func show(
        url: URL,
        item: ClipboardHistoryItem,
        anchorX: CGFloat,
        parentPanelTop: CGFloat,
        screenFrame: CGRect
    ) {
        previewSize = ClipboardHistoryPreviewLayout.size(for: item)
        let frame = ClipboardHistoryPreviewLayout.frame(
            size: previewSize,
            anchorX: anchorX,
            panelTop: parentPanelTop,
            screenFrame: screenFrame
        )
        panel.setFrame(frame, display: true)
        layoutContent(size: frame.size)
        titleField.stringValue = item.kind.title
        sourceField.stringValue = item.sourceApplicationName ?? ""
        previewView.previewItem = url as NSURL
        previewView.refreshPreviewItem()
        panel.orderFrontRegardless()
    }

    func reposition(
        anchorX: CGFloat,
        parentPanelTop: CGFloat,
        screenFrame: CGRect
    ) {
        guard isVisible else { return }
        let frame = ClipboardHistoryPreviewLayout.frame(
            size: previewSize,
            anchorX: anchorX,
            panelTop: parentPanelTop,
            screenFrame: screenFrame
        )
        panel.setFrame(frame, display: true)
        layoutContent(size: frame.size)
    }

    func close() {
        previewView.previewItem = nil
        panel.orderOut(nil)
    }

    private func layoutContent(size: CGSize) {
        let headerHeight: CGFloat = 38
        container.frame = CGRect(origin: .zero, size: size)
        titleField.frame = CGRect(x: 14, y: size.height - 29, width: size.width * 0.48, height: 20)
        sourceField.frame = CGRect(
            x: size.width * 0.5,
            y: size.height - 29,
            width: size.width * 0.5 - 14,
            height: 20
        )
        previewView.frame = CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: size.height - headerHeight
        )
    }
}
