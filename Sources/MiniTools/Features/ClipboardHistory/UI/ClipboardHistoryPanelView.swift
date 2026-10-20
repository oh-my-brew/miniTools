import AppKit
import SwiftUI

enum ClipboardHistoryPanelMetrics {
    static let height: CGFloat = 320
    static let screenInset: CGFloat = 12
    static let bottomInset: CGFloat = 12
    static let headerHeight: CGFloat = 48
    static let cardWidth: CGFloat = 236
    static let cardHeight: CGFloat = 236
    static let cardHeaderHeight: CGFloat = 58
    static let cardSpacing: CGFloat = 14
    static let cornerRadius: CGFloat = 22
}

private enum ClipboardHistoryPanelCoordinateSpace {
    static let name = "ClipboardHistoryPanel"
}

private struct SelectedClipboardCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

struct ClipboardHistoryPanelView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let onPaste: (ClipboardHistoryItem, Bool) -> Void
    let onOpenSettings: () -> Void
    let onSelectedCardFrameChange: (CGRect?) -> Void

    @State private var timelinePosition = ScrollPosition(x: 0)
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            header
            timeline
        }
        .padding(10)
        .featurePanelSurface(cornerRadius: ClipboardHistoryPanelMetrics.cornerRadius)
        .coordinateSpace(name: ClipboardHistoryPanelCoordinateSpace.name)
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.searchFocusRequestID) { _, _ in searchFocused = true }
        .onPreferenceChange(SelectedClipboardCardFramePreferenceKey.self) {
            onSelectedCardFrameChange($0)
        }
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 12) {
                searchControl

                Label("剪贴板历史记录", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 15)
                    .frame(height: 38)
                    .featurePanelGlassControl(selected: true, in: Capsule())
            }

            HStack {
                if let message = viewModel.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 360, alignment: .leading)
                }
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "ellipsis")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .featurePanelGlassControl(in: Circle())
                .help("剪贴板历史设置")
            }
        }
        .frame(height: ClipboardHistoryPanelMetrics.headerHeight)
    }

    private var searchControl: some View {
        let expanded = viewModel.isSearchEditing || !viewModel.query.isEmpty

        return HStack(spacing: expanded ? 8 : 0) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("搜索剪贴板历史", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .frame(width: expanded ? 294 : 0)
                .opacity(expanded ? 1 : 0)
                .allowsHitTesting(expanded)
        }
        .padding(.horizontal, expanded ? 14 : 10)
        .frame(width: expanded ? 350 : 38, height: 38)
        .contentShape(Capsule())
        .featurePanelGlassControl(in: Capsule())
        .onTapGesture { viewModel.focusSearch() }
        .animation(.easeOut(duration: 0.12), value: expanded)
    }

    private var timeline: some View {
        Group {
            if viewModel.visibleItems.isEmpty {
                ContentUnavailableView(
                    viewModel.query.isEmpty ? "暂无剪贴板历史" : "没有匹配结果",
                    systemImage: "clipboard"
                )
            } else {
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
                .scrollPosition($timelinePosition)
                .onScrollGeometryChange(for: CGRect.self) { geometry in
                    geometry.visibleRect
                } action: { _, rect in
                    viewModel.updateViewport(rect)
                }
                .onChange(of: viewModel.scrollRequest, initial: true) { _, request in
                    if request.animated {
                        withAnimation(.easeOut(duration: 0.14)) {
                            timelinePosition.scrollTo(x: request.offset)
                        }
                    } else {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { timelinePosition.scrollTo(x: request.offset) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clipboardCard(_ item: ClipboardHistoryItem, number: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardTitle(item))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(
                            ClipboardHistoryRelativeTimeFormatter.string(
                                from: item.copiedAt,
                                relativeTo: context.date
                            )
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Spacer()
                sourceApplicationIcon(item)
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .frame(height: ClipboardHistoryPanelMetrics.cardHeaderHeight)
            .background(cardHeaderColor(item))

            cardContent(item)
                .frame(
                    width: ClipboardHistoryPanelMetrics.cardWidth,
                    height: ClipboardHistoryPanelMetrics.cardHeight
                        - ClipboardHistoryPanelMetrics.cardHeaderHeight
                )
                .clipped()
                .background(Color(nsColor: .controlBackgroundColor))
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
        .overlay(alignment: .bottomTrailing) {
            if viewModel.showsNumberShortcuts, number <= 9 {
                shortcutBadge(number)
                    .padding(9)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .background {
            if item.id == viewModel.selectedID {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SelectedClipboardCardFramePreferenceKey.self,
                        value: proxy.frame(in: .named(ClipboardHistoryPanelCoordinateSpace.name))
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPaste(item, false) }
        .onTapGesture { viewModel.select(item.id) }
    }

    @ViewBuilder
    private func cardContent(_ item: ClipboardHistoryItem) -> some View {
        if let data = viewModel.thumbnails[item.id], let image = NSImage(data: data) {
            ZStack {
                ClipboardHistoryCheckerboard()
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(10)
            }
            .overlay(alignment: .bottom) {
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.58), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(7)
                }
            }
        } else if item.kind == .link,
                  let link = ClipboardHistoryLinkPresentation(text: item.plainText) {
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "safari")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(link.displayURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
        } else if item.kind == .files {
            let fileURLs = viewModel.fileURLs[item.id] ?? []
            let fileURL = fileURLs.first
            VStack(spacing: 0) {
                Spacer(minLength: 8)
                Image(nsImage: fileIcon(for: fileURL))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 100, maxHeight: 100)
                Spacer(minLength: 8)
                Text(filePathDescription(fileURLs: fileURLs, fallback: item.summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
        } else if item.kind == .color, let color = colorValue(item.plainText) {
            ZStack {
                color
                Text(item.plainText ?? "")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        Color(
                            nsColor: ClipboardHistoryColorPresentation(text: item.plainText)?
                                .foregroundColor ?? .labelColor
                        )
                    )
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.summary)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(.primary)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 4)
                Text("\(item.plainText?.count ?? item.summary.count) 个字符")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
    }

    @ViewBuilder
    private func sourceApplicationIcon(_ item: ClipboardHistoryItem) -> some View {
        if let appearance = viewModel.applicationAppearance(for: item) {
            Image(nsImage: appearance.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 50, height: 50)
                .help(item.sourceApplicationName ?? item.sourceBundleIdentifier ?? "")
        } else {
            Image(systemName: "app")
                .font(.system(size: 25))
                .frame(width: 50, height: 50)
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutBadge(_ number: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "text.justify.leading")
                .font(.system(size: 10, weight: .semibold))
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func cardTitle(_ item: ClipboardHistoryItem) -> String {
        guard item.kind == .files else { return item.kind.title }
        let count = max(1, viewModel.fileURLs[item.id]?.count ?? 0)
        return "\(count)个文件"
    }

    private func fileIcon(for URL: URL?) -> NSImage {
        guard let URL else {
            return NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: URL.path)
    }

    private func filePathDescription(fileURLs: [URL], fallback: String) -> String {
        guard let first = fileURLs.first else { return fallback }
        guard fileURLs.count > 1 else { return first.path }
        return "\(first.path) 等 \(fileURLs.count) 个文件"
    }

    private func cardHeaderColor(_ item: ClipboardHistoryItem) -> Color {
        guard let appearance = viewModel.applicationAppearance(for: item) else {
            return Color(nsColor: ClipboardHistoryIconPalette.monochromeFallback.nsColor)
        }
        return Color(nsColor: appearance.headerColor)
    }

    private func colorValue(_ value: String?) -> Color? {
        guard let presentation = ClipboardHistoryColorPresentation(text: value) else { return nil }
        return Color(nsColor: presentation.color.nsColor)
    }
}

private struct ClipboardHistoryCheckerboard: View {
    private let cellSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for row in 0..<rows {
                for column in 0..<columns {
                    let color = (row + column).isMultiple(of: 2)
                        ? Color(nsColor: .windowBackgroundColor)
                        : Color(nsColor: .underPageBackgroundColor)
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * cellSize,
                                y: CGFloat(row) * cellSize,
                                width: cellSize,
                                height: cellSize
                            )
                        ),
                        with: .color(color)
                    )
                }
            }
        }
    }
}
