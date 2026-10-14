import AppKit
import SwiftUI

enum FeaturePanelMetrics {
    static let preferredWidth: CGFloat = 680
    static let minimumWidth: CGFloat = 320
    static let encodingPanelHeight: CGFloat = 568

    static let switcherHeight: CGFloat = 52
    static let switcherContentSpacing: CGFloat = 10
    static let surfaceCornerRadius: CGFloat = 18

    static let footerHeight: CGFloat = 38
    static let footerHorizontalPadding: CGFloat = 14
    static let footerItemSpacing: CGFloat = 8
    static let footerFontSize: CGFloat = 10

    static let safariPreferredRowHeight: CGFloat = 42
    static let safariPreferredRowSpacing: CGFloat = 2
    static let safariListVerticalPadding: CGFloat = 12
    static let safariMinimumBodyHeight: CGFloat = 47
    static let separatorHeight: CGFloat = 1

    static let screenHorizontalInset: CGFloat = 40
    static let screenVerticalInset: CGFloat = 100
    static let panelTopInset: CGFloat = 90

    static var safariFixedHeight: CGFloat {
        switcherHeight
            + switcherContentSpacing
            + footerHeight
            + safariListVerticalPadding
            + separatorHeight
    }

    static func panelWidth(availableWidth: CGFloat) -> CGFloat {
        min(preferredWidth, max(minimumWidth, availableWidth))
    }
}

enum FeaturePanelMaterial {
    static var controlBackdrop: Color {
        Color(nsColor: .windowBackgroundColor).opacity(0.58)
    }

    static let selectionFillOpacity = 0.16
    static let selectionStrokeOpacity = 0.24
}

private struct FeaturePanelSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .glassEffect(.regular, in: shape)
            .glassEffectTransition(.identity)
            .clipShape(shape)
    }
}

private struct FeaturePanelSelection: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(
                isSelected
                    ? Color.accentColor.opacity(FeaturePanelMaterial.selectionFillOpacity)
                    : Color.clear,
                in: shape
            )
            .overlay {
                if isSelected {
                    shape.stroke(
                        Color.accentColor.opacity(FeaturePanelMaterial.selectionStrokeOpacity),
                        lineWidth: 0.5
                    )
                }
            }
    }
}

struct FeaturePanelFooter<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(.system(size: FeaturePanelMetrics.footerFontSize))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, FeaturePanelMetrics.footerHorizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: FeaturePanelMetrics.footerHeight,
                maxHeight: FeaturePanelMetrics.footerHeight
            )
    }
}

struct FeaturePanelShortcutHints: View {
    let leading: [String]
    let trailing: [String]

    var body: some View {
        HStack(spacing: FeaturePanelMetrics.footerItemSpacing) {
            ForEach(leading, id: \.self, content: Text.init)
            Spacer(minLength: 12)
            ForEach(trailing, id: \.self, content: Text.init)
        }
    }
}

extension View {
    func featurePanelSurface(
        cornerRadius: CGFloat = FeaturePanelMetrics.surfaceCornerRadius
    ) -> some View {
        modifier(FeaturePanelSurface(cornerRadius: cornerRadius))
    }

    func featurePanelSelection(_ isSelected: Bool, cornerRadius: CGFloat) -> some View {
        modifier(FeaturePanelSelection(isSelected: isSelected, cornerRadius: cornerRadius))
    }

    func featurePanelGlassControl<S: Shape>(
        selected: Bool = false,
        in shape: S
    ) -> some View {
        glassEffect(
            selected
                ? .regular.tint(Color.accentColor.opacity(0.2))
                : .regular,
            in: shape
        )
        .glassEffectTransition(.identity)
        .background(FeaturePanelMaterial.controlBackdrop, in: shape)
        .clipShape(shape)
    }
}
