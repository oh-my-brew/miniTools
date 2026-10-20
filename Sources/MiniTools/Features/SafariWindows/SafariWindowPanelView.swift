import SwiftUI

struct SafariWindowPanelView: View {
    @ObservedObject var viewModel: SafariWindowPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider().opacity(0.55)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.windows.isEmpty {
            Text("正在读取 Safari 窗口…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, viewModel.windows.isEmpty {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
        } else {
            VStack(spacing: viewModel.layout.rowSpacing) {
                ForEach(Array(viewModel.windows.enumerated()), id: \.element.id) { index, window in
                    windowRow(window, at: index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(6)
        }
    }

    private func windowRow(_ window: SafariWindowItem, at index: Int) -> some View {
        let selected = viewModel.selectedWindowID == window.id

        return HStack(spacing: 11) {
            if let shortcut = viewModel.shortcut(at: index) {
                Text(shortcut.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 24, height: min(24, viewModel.layout.rowHeight - 6))
                    .background(Color.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Color.clear.frame(width: 24)
            }

            Text(window.title)
                .font(.system(size: viewModel.layout.rowHeight < 32 ? 11 : 13, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .frame(height: viewModel.layout.rowHeight)
        .contentShape(Rectangle())
        .featurePanelSelection(selected, cornerRadius: 8)
    }

    private var footer: some View {
        FeaturePanelFooter {
            if let errorMessage = viewModel.errorMessage, !viewModel.windows.isEmpty {
                HStack {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                }
            } else {
                FeaturePanelShortcutHints(
                    leading: ["字母直达", "↑↓/J/K 选择", "N 新建窗口", "M 打开未分组"],
                    trailing: ["Enter 执行", "Tab 切换", "Esc 关闭"]
                )
            }
        }
    }
}
