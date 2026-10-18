import AppKit
import SwiftUI

enum ClipboardHistoryPanelMetrics {
    static let height: CGFloat = 244
    static let screenInset: CGFloat = 12
    static let bottomInset: CGFloat = 12
    static let headerHeight: CGFloat = 48
    static let cardWidth: CGFloat = 190
    static let cardHeight: CGFloat = 166
    static let cardSpacing: CGFloat = 14
    static let cornerRadius: CGFloat = 22
}

struct ClipboardHistoryPanelView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let onPaste: (ClipboardHistoryItem, Bool) -> Void
    let onOpenSettings: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            header
            timeline
        }
        .padding(10)
        .featurePanelSurface(cornerRadius: ClipboardHistoryPanelMetrics.cornerRadius)
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.searchFocusRequestID) { _, _ in searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索剪贴板历史", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: 360, minHeight: 38)
            .featurePanelGlassControl(in: Capsule())

            Label("剪贴板历史记录", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 15)
                .frame(height: 38)
                .featurePanelGlassControl(selected: true, in: Capsule())

            Spacer()

            if let message = viewModel.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onOpenSettings) {
                Image(systemName: "ellipsis")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .featurePanelGlassControl(in: Circle())
            .help("剪贴板历史设置")
        }
        .frame(height: ClipboardHistoryPanelMetrics.headerHeight)
    }

    private var timeline: some View {
        Group {
            if viewModel.visibleItems.isEmpty {
                ContentUnavailableView(
                    viewModel.query.isEmpty ? "暂无剪贴板历史" : "没有匹配结果",
                    systemImage: "clipboard"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: ClipboardHistoryPanelMetrics.cardSpacing) {
                            ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) {
                                index, item in
                                clipboardCard(item, number: index + 1)
                                    .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .onChange(of: viewModel.selectedID) { _, selectedID in
                        guard let selectedID else { return }
                        withAnimation(.easeOut(duration: 0.14)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clipboardCard(_ item: ClipboardHistoryItem, number: Int) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind.title)
                        .font(.system(size: 14, weight: .bold))
                    Text(item.copiedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if number <= 9 {
                    Text("⌘\(number)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                sourceApplicationIcon(item)
            }
            .padding(12)
            .background(cardHeaderColor(item))

            cardContent(item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        }
        .frame(
            width: ClipboardHistoryPanelMetrics.cardWidth,
            height: ClipboardHistoryPanelMetrics.cardHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    item.id == viewModel.selectedID ? Color.accentColor : Color.white.opacity(0.12),
                    lineWidth: item.id == viewModel.selectedID ? 2 : 0.5
                )
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPaste(item, false) }
        .onTapGesture { viewModel.select(item.id) }
    }

    @ViewBuilder
    private func cardContent(_ item: ClipboardHistoryItem) -> some View {
        if let data = viewModel.thumbnails[item.id], let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
                .overlay(alignment: .bottom) {
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(7)
                    }
                }
        } else if item.kind == .color, let color = colorValue(item.plainText) {
            ZStack {
                color
                Text(item.plainText ?? "")
                    .font(.headline.monospaced())
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        } else {
            Text(item.summary)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }

    @ViewBuilder
    private func sourceApplicationIcon(_ item: ClipboardHistoryItem) -> some View {
        if let bundleIdentifier = item.sourceBundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
                .help(item.sourceApplicationName ?? bundleIdentifier)
        } else {
            Image(systemName: "app")
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
        }
    }

    private func cardHeaderColor(_ item: ClipboardHistoryItem) -> Color {
        switch item.kind {
        case .image: Color.red.opacity(0.78)
        case .link: Color.blue.opacity(0.72)
        case .color: Color.purple.opacity(0.7)
        case .files: Color.orange.opacity(0.72)
        case .text, .richText: Color.indigo.opacity(0.72)
        }
    }

    private func colorValue(_ value: String?) -> Color? {
        guard var value else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        return Color(
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }
}
