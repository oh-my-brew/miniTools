import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WindowCompatibilitySettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var selectingApplication = false
    @State private var restoringDefaults = false
    @State private var message: String?

    var body: some View {
        Section {
            ForEach(settings.windowCompatibilityApplications.sorted(), id: \.self) { identifier in
                applicationRow(identifier)
            }
            if settings.windowCompatibilityApplications.isEmpty {
                Text("尚未添加应用，所有应用均使用常规调整方式。")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("添加应用…") {
                    message = nil
                    selectingApplication = true
                }
                Spacer()
                Button("恢复默认名单") { restoringDefaults = true }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("窗口调整兼容应用")
        } footer: {
            Text("当应用调整窗口时出现大小或位置不到位，可加入此列表试用兼容方式。添加、移除立即生效；移除后使用常规方式。配置仅保存在本机。")
        }
        .fileImporter(isPresented: $selectingApplication, allowedContentTypes: [.applicationBundle]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard let bundle = Bundle(url: url), let info = bundle.infoDictionary,
                      let application = WindowCompatibilityApplication(info: info) else {
                    message = "无法读取应用标识，请选择有效的 .app 应用。"
                    return
                }
                if settings.windowCompatibilityApplications.contains(application.bundleIdentifier) {
                    message = "\(application.name) 已在兼容名单中。"
                } else {
                    settings.addWindowCompatibilityApplication(application.bundleIdentifier)
                    message = "已添加 \(application.name)，下次窗口操作即使用兼容方式。"
                }
            case .failure(let error):
                message = "无法选择应用：\(error.localizedDescription)"
            }
        }
        .confirmationDialog("恢复默认兼容名单？", isPresented: $restoringDefaults) {
            Button("恢复默认名单") {
                settings.restoreDefaultWindowCompatibilityApplications()
                message = nil
            }
        } message: {
            Text("将恢复 Safari、Finder、Codex、ChatGPT、QQ、飞书、备忘录七项，并移除自行添加的应用。")
        }
    }

    private func applicationRow(_ identifier: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        let name = url.map { FileManager.default.displayName(atPath: $0.path) }
            ?? WindowCompatibilityApplication.defaultNames[identifier] ?? identifier
        return HStack(spacing: 10) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().scaledToFit().frame(width: 24, height: 24)
            } else {
                Image(systemName: "app").frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(identifier).font(.caption).foregroundStyle(.secondary)
                if url == nil {
                    Text("未找到此应用，配置仍会保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("移除") {
                settings.removeWindowCompatibilityApplication(identifier)
                message = nil
            }
            .help("对此应用恢复常规窗口调整方式")
        }
    }
}
