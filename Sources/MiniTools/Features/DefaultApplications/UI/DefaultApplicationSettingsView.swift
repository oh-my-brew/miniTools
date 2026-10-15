import SwiftUI

struct DefaultApplicationSettingsView: View {
    @StateObject private var model: DefaultApplicationSettingsModel

    init(model: DefaultApplicationSettingsModel = DefaultApplicationSettingsModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Section {
            LabeledContent("安装状态") {
                HStack(spacing: 8) {
                    if let application = model.sublimeTextApplication {
                        Label(application.name, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("未安装", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    Button("刷新") {
                        model.refresh()
                    }
                    .disabled(model.isUpdating)
                }
            }
        } header: {
            Text("Sublime Text")
        } footer: {
            Text("miniTools 只查询已安装应用，不会启动 Sublime Text。")
        }

        Section {
            ForEach(model.rows) { row in
                fileTypeRow(row)
            }
        } header: {
            Text("文件类型")
        } footer: {
            Text("每次修改都会由 macOS 针对该文件类型显示系统确认。确认后 miniTools 会重新查询实际默认应用；此页不提供含糊的“恢复默认”操作。")
        }
        .task {
            model.refresh()
        }
    }

    private func fileTypeRow(_ row: DefaultApplicationRowState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("当前默认：\(row.currentApplication?.name ?? "未找到默认应用")")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if row.isUpdating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("等待 macOS 确认…")
                                .foregroundStyle(.secondary)
                        }
                    } else if model.isSublimeTextDefault(for: row) {
                        Label("已设置", systemImage: "checkmark")
                            .foregroundStyle(.green)
                    } else {
                        Button("设为 Sublime Text") {
                            Task {
                                await model.setSublimeText(for: row.id)
                            }
                        }
                        .disabled(model.sublimeTextApplication == nil || model.isUpdating)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.fileType.title)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(row.fileType.extensionSummary) · \(row.fileType.expectedContentTypeIdentifier)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let message = row.message {
                Label(
                    message.text,
                    systemImage: message.kind == .success
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10))
                .foregroundStyle(message.kind == .success ? Color.green : Color.orange)
            }
        }
    }
}
