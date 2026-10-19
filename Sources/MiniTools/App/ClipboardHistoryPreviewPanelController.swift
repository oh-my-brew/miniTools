import AppKit
import QuickLookUI
import QuartzCore

@MainActor
final class ClipboardHistoryPreviewPanelController: NSObject {
    private enum Metrics {
        static let pointerHeight = ClipboardHistoryPreviewShape.pointerHeight
        static let headerHeight: CGFloat = 48
        static let footerHeight: CGFloat = 34
        static let contentInset: CGFloat = 10
    }

    private let panel: NSPanel
    private let container = NSVisualEffectView()
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let closeButton = NSButton()
    private let titleField = NSTextField(labelWithString: "")
    private let sourceField = NSTextField(labelWithString: "")
    private let previewView: QLPreviewView
    private let textScrollView = NSScrollView()
    private let textView = NSTextView()
    private let textFooterField = NSTextField(labelWithString: "")
    private let colorView = NSView()
    private let colorHexField = NSTextField(labelWithString: "")
    private let colorFooterField = NSTextField(labelWithString: "")
    private var previewSize = CGSize.zero

    override init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        previewView = QLPreviewView(frame: .zero, style: .compact)
        super.init()

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
        container.layer?.mask = maskLayer
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.separatorColor.withAlphaComponent(0.72).cgColor
        borderLayer.lineWidth = 1
        container.layer?.addSublayer(borderLayer)

        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "关闭预览"
        )
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed)

        titleField.font = .systemFont(ofSize: 15, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        sourceField.font = .systemFont(ofSize: 12)
        sourceField.textColor = .secondaryLabelColor
        sourceField.alignment = .right
        sourceField.lineBreakMode = .byTruncatingTail

        previewView.shouldCloseWithWindow = true
        previewView.autostarts = false

        textScrollView.drawsBackground = false
        textScrollView.hasVerticalScroller = true
        textScrollView.autohidesScrollers = true
        textScrollView.verticalScrollElasticity = .none
        textScrollView.documentView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(calibratedWhite: 0.045, alpha: 0.96)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        textFooterField.font = .systemFont(ofSize: 12, weight: .medium)
        textFooterField.textColor = .tertiaryLabelColor

        colorView.wantsLayer = true
        colorView.layer?.cornerRadius = 6
        colorView.layer?.cornerCurve = .continuous
        colorHexField.font = .systemFont(ofSize: 31, weight: .bold)
        colorHexField.alignment = .center
        colorFooterField.font = .systemFont(ofSize: 12, weight: .medium)
        colorFooterField.textColor = .tertiaryLabelColor
        colorFooterField.lineBreakMode = .byTruncatingTail

        for view in [
            previewView,
            textScrollView,
            textFooterField,
            colorView,
            colorHexField,
            colorFooterField,
            closeButton,
            titleField,
            sourceField
        ] {
            container.addSubview(view)
        }
        panel.contentView = container
    }

    var isVisible: Bool { panel.isVisible }

    func show(
        url: URL?,
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
        layoutContent(size: frame.size, pointerX: anchorX - frame.minX)
        titleField.stringValue = item.kind.title
        sourceField.stringValue = item.sourceApplicationName ?? ""
        configureContent(url: url, item: item)
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
        layoutContent(size: frame.size, pointerX: anchorX - frame.minX)
    }

    func close() {
        previewView.previewItem = nil
        panel.orderOut(nil)
    }

    @objc private func closeButtonPressed() {
        close()
    }

    private func configureContent(url: URL?, item: ClipboardHistoryItem) {
        let isText = item.kind == .text || item.kind == .richText
        let isColor = item.kind == .color
        previewView.isHidden = isText || isColor
        textScrollView.isHidden = !isText
        textFooterField.isHidden = !isText
        colorView.isHidden = !isColor
        colorHexField.isHidden = !isColor
        colorFooterField.isHidden = !isColor

        if isText {
            let text = item.plainText ?? item.summary
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            textView.textStorage?.setAttributedString(
                NSAttributedString(
                    string: text,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: paragraph
                    ]
                )
            )
            textFooterField.stringValue = ClipboardHistoryTextMetrics(text: text).description
            textView.scrollToBeginningOfDocument(nil)
            previewView.previewItem = nil
        } else if isColor, let presentation = ClipboardHistoryColorPresentation(text: item.plainText) {
            colorView.layer?.backgroundColor = presentation.color.nsColor.cgColor
            colorHexField.stringValue = presentation.hex
            colorHexField.textColor = presentation.foregroundColor
            colorFooterField.stringValue = [
                presentation.rgbDescription,
                presentation.hslDescription,
                presentation.hsbDescription
            ].joined(separator: "  ·  ")
            previewView.previewItem = nil
        } else {
            previewView.previewItem = url.map { $0 as NSURL }
            previewView.refreshPreviewItem()
        }
    }

    private func layoutContent(size: CGSize, pointerX: CGFloat) {
        container.frame = CGRect(origin: .zero, size: size)
        let shape = ClipboardHistoryPreviewShape.path(size: size, pointerX: pointerX)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = container.bounds
        maskLayer.path = shape
        borderLayer.frame = container.bounds
        borderLayer.path = shape
        CATransaction.commit()

        let headerY = size.height - Metrics.headerHeight
        closeButton.frame = CGRect(x: 10, y: headerY + 11, width: 26, height: 26)
        titleField.frame = CGRect(x: 43, y: headerY + 13, width: size.width * 0.46, height: 22)
        sourceField.frame = CGRect(
            x: size.width * 0.56,
            y: headerY + 14,
            width: size.width * 0.44 - 16,
            height: 20
        )

        previewView.frame = CGRect(
            x: 0,
            y: Metrics.pointerHeight,
            width: size.width,
            height: size.height - Metrics.headerHeight - Metrics.pointerHeight
        )

        let customContentWidth = size.width - Metrics.contentInset * 2
        let customContentY = Metrics.pointerHeight + Metrics.footerHeight
        let customContentHeight = size.height
            - Metrics.headerHeight
            - Metrics.footerHeight
            - Metrics.pointerHeight
            - Metrics.contentInset
        let customFrame = CGRect(
            x: Metrics.contentInset,
            y: customContentY,
            width: customContentWidth,
            height: customContentHeight
        )
        textScrollView.frame = customFrame
        textView.frame = CGRect(origin: .zero, size: customFrame.size)
        textView.minSize = NSSize(width: 0, height: customFrame.height)
        textView.maxSize = NSSize(width: customFrame.width, height: .greatestFiniteMagnitude)
        textFooterField.frame = CGRect(
            x: 16,
            y: Metrics.pointerHeight + 7,
            width: size.width - 32,
            height: 18
        )

        colorView.frame = customFrame
        colorHexField.frame = CGRect(
            x: customFrame.minX + 20,
            y: customFrame.midY - 22,
            width: customFrame.width - 40,
            height: 44
        )
        colorFooterField.frame = textFooterField.frame
    }

}
