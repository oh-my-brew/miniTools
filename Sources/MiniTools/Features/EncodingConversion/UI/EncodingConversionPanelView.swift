import AppKit
import SwiftUI

struct EncodingConversionPanelView: View {
    @ObservedObject var viewModel: EncodingConversionPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            actionList
            Divider().opacity(0.55)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            contentThumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.contentSummary)
                    .font(.system(size: 13, weight: .semibold))
                if !viewModel.contentPreview.isEmpty {
                    Text(viewModel.contentPreview)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()

            if viewModel.isAnalyzing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在识别…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var contentThumbnail: some View {
        if
            let image = viewModel.thumbnailImage
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 46, height: 46)
        }
    }

    private var actionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: []) {
                    if viewModel.filteredSections.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.filteredSections) { section in
                            Text(sectionHeader(section).uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 18)
                                .padding(.top, 10)
                                .padding(.bottom, 3)

                            ForEach(section.actions) { action in
                                let shortcutNumber = viewModel.directShortcutNumber(
                                    forActionID: action.id
                                )
                                actionRow(action, shortcutNumber: shortcutNumber)
                                    .id(ActionRowRenderID(
                                        actionID: action.id,
                                        searchQuery: viewModel.normalizedSearchQuery,
                                        shortcutNumber: shortcutNumber
                                    ))
                                    .id(action.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: viewModel.selectedActionID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func actionRow(
        _ action: ToolAction,
        shortcutNumber: Int?
    ) -> some View {
        let selected = viewModel.selectedActionID == action.id

        return HStack(spacing: 12) {
            Image(systemName: action.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    highlightedTitle(action.title)
                        .font(.system(size: 13, weight: .medium))
                    if action.isRecommended {
                        Text("推荐")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.16))
                            .clipShape(Capsule())
                    }
                }
                Text(action.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer()

            if let shortcutNumber, shortcutNumber <= 9 {
                Text("\(shortcutNumber)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .featurePanelSelection(selected, cornerRadius: 9)
        .padding(.horizontal, 8)
    }

    private struct ActionRowRenderID: Hashable {
        let actionID: String
        let searchQuery: String
        let shortcutNumber: Int?
    }

    private func sectionHeader(_ section: ToolActionSection) -> String {
        section.id == "search"
            ? "\(section.title) · \(section.actions.count)"
            : section.title
    }

    private func highlightedTitle(_ value: String) -> Text {
        guard viewModel.isSearching else { return Text(value) }
        var attributed = AttributedString(value)
        for token in viewModel.searchTokens {
            if let range = attributed.range(of: token, options: .caseInsensitive) {
                attributed[range].foregroundColor = .accentColor
                attributed[range].font = .system(size: 13, weight: .semibold)
            }
        }
        return Text(attributed)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.isSearching ? "magnifyingglass" : "clipboard")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(emptyStateMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var emptyStateMessage: String {
        if let error = viewModel.errorMessage, viewModel.sections.isEmpty {
            return error
        }
        if viewModel.isSearching {
            return "没有匹配“\(viewModel.searchQuery)”的功能"
        }
        return "没有可执行操作"
    }

    private var footer: some View {
        FeaturePanelFooter {
            if let error = viewModel.errorMessage, !viewModel.sections.isEmpty {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                }
            } else if viewModel.isExecuting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在处理…")
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            } else {
                FeaturePanelShortcutHints(
                    leading: ["⌘1–9 直达", "↑↓ 选择"],
                    trailing: [
                        "Enter 执行",
                        "Tab 切换",
                        viewModel.isSearching ? "Esc 清空" : "Esc 关闭"
                    ]
                )
            }
        }
    }
}
