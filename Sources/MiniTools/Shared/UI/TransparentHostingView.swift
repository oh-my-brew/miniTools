import AppKit
import SwiftUI

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    var onWillDraw: (() -> Void)?

    override func viewWillDraw() {
        super.viewWillDraw()
        if window?.isVisible == true { onWillDraw?() }
    }

    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
