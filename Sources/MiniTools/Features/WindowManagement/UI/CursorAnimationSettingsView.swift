import AppKit
import SwiftUI

struct CursorAnimationSettingsView: View {
    @ObservedObject var settings: AppSettings

    private let columns = [
        GridItem(.adaptive(minimum: 138, maximum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("触发鼠标跨屏后，从已启用效果中轮换播放。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全部启用") {
                    setAllStyles(enabled: true)
                }
                Button("全部关闭") {
                    setAllStyles(enabled: false)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(CursorHighlightStyle.allCases) { style in
                    styleCard(style)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func styleCard(_ style: CursorHighlightStyle) -> some View {
        let isEnabled = settings.isCursorHighlightStyleEnabled(style)
        return Button {
            settings.updateCursorHighlightStyle(style, isEnabled: !isEnabled)
        } label: {
            VStack(spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    styleArtwork(style)
                        .frame(width: 76, height: 76)

                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                        .symbolRenderingMode(.hierarchical)
                        .offset(x: 16, y: -4)
                }

                Text(style.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                isEnabled ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isEnabled ? Color.accentColor.opacity(0.48) : Color.secondary.opacity(0.15),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help("\(isEnabled ? "关闭" : "启用")“\(style.title)”")
        .accessibilityLabel("\(style.title)，\(isEnabled ? "已启用" : "未启用")")
    }

    @ViewBuilder
    private func styleArtwork(_ style: CursorHighlightStyle) -> some View {
        if style == .spectrumFlow {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.pink, .purple, .blue, .cyan, .green, .yellow, .pink],
                            center: .center
                        ),
                        lineWidth: 8
                    )
                    .shadow(color: .cyan.opacity(0.55), radius: 8)
                Circle().fill(.white.opacity(0.10)).padding(13)
            }
            .padding(8)
        } else if style == .siriFluid {
            ZStack {
                Circle().fill(.blue.gradient).offset(x: -11, y: 8)
                Circle().fill(.pink.gradient).offset(x: 12, y: 5)
                Circle().fill(.cyan.gradient).offset(y: -12)
            }
            .blur(radius: 5)
            .padding(16)
            .background(.purple.opacity(0.12), in: Circle())
        } else if let artwork = SharinganArtwork.renderedArtwork(for: style) {
            Image(nsImage: NSImage(cgImage: artwork.image, size: NSSize(width: 76, height: 76)))
                .resizable()
                .scaledToFit()
                .shadow(color: Color(nsColor: artwork.glowColor).opacity(0.45), radius: 7)
        } else {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
        }
    }

    private func setAllStyles(enabled: Bool) {
        for style in CursorHighlightStyle.allCases {
            settings.updateCursorHighlightStyle(style, isEnabled: enabled)
        }
    }
}
