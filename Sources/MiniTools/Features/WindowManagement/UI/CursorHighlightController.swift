import AppKit

@MainActor
final class CursorHighlightController {
    private var window: NSWindow?
    private var dismissWorkItem: DispatchWorkItem?
    private var nextStyleIndex = 0

    func show(
        atAccessibilityPoint point: CGPoint,
        enabledStyles: Set<CursorHighlightStyle>
    ) {
        let styles = CursorHighlightStyle.allCases.filter(enabledStyles.contains)
        guard !styles.isEmpty else { return }
        let style = styles[nextStyleIndex % styles.count]
        nextStyleIndex = (nextStyleIndex + 1) % styles.count

        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitPoint = CGPoint(x: point.x, y: primaryMaxY - point.y)
        show(style: style, atAppKitPoint: appKitPoint)
    }

    private func show(style: CursorHighlightStyle, atAppKitPoint point: CGPoint) {
        dismissWorkItem?.cancel()
        window?.orderOut(nil)

        let effectSize = style.effectSize
        let frame = CGRect(
            x: point.x - effectSize.width / 2,
            y: point.y - effectSize.height / 2,
            width: effectSize.width,
            height: effectSize.height
        )
        let overlay = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.level = .screenSaver
        overlay.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
        ]

        let highlightView = CursorHighlightEffectFactory.makeView(
            style: style,
            frame: CGRect(origin: .zero, size: effectSize)
        )
        overlay.contentView = highlightView
        overlay.orderFrontRegardless()
        highlightView.startAnimation()
        window = overlay

        let workItem = DispatchWorkItem { [weak self, weak overlay] in
            overlay?.orderOut(nil)
            if self?.window === overlay { self?.window = nil }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + style.effectLifetime,
            execute: workItem
        )
    }
}

private extension CursorHighlightStyle {
    var effectSize: CGSize {
        switch self {
        case .spectrumFlow, .siriFluid:
            let side = CursorHighlightPresentationMetrics.size(152)
            return CGSize(width: side, height: side)
        default:
            return SharinganCursorHighlightView.canvasSize
        }
    }

    var effectLifetime: TimeInterval {
        switch self {
        case .spectrumFlow: 2.05
        case .siriFluid: 2.32
        default: 2.26
        }
    }
}

@MainActor
private enum CursorHighlightEffectFactory {
    static func makeView(
        style: CursorHighlightStyle,
        frame: CGRect
    ) -> CursorHighlightEffectView {
        switch style {
        case .spectrumFlow:
            SpectrumCursorHighlightView(frame: frame)
        case .siriFluid:
            SiriFluidCursorHighlightView(frame: frame)
        default:
            SharinganCursorHighlightView(style: style, frame: frame)
        }
    }
}
