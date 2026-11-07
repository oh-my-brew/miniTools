import AppKit
import CoreGraphics
import SwiftUI

/// Queries only while settings are shown; requests are explicit button actions.
struct GeneralAuthorizationSettingsView: View {
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false

    var body: some View {
        Section {
            permissionRow(
                title: "辅助功能", subtitle: "用于窗口调整、Safari 窗口和粘贴操作",
                granted: accessibilityGranted, pane: "Privacy_Accessibility"
            ) {
                _ = AccessibilityAuthorization.requestPermission()
            }
            permissionRow(
                title: "输入监控", subtitle: "用于鼠标侧键操作",
                granted: inputMonitoringGranted, pane: "Privacy_ListenEvent"
            ) {
                _ = CGRequestListenEventAccess()
            }
        } header: {
            Text("授权")
        } footer: {
            Text("授权由 macOS 管理；从系统设置返回后会刷新状态。")
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func permissionRow(
        title: String, subtitle: String, granted: Bool, pane: String,
        request: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Text(granted ? "已授权" : "未授权")
                    .foregroundStyle(.secondary)
                Button(granted ? "管理授权" : "前往授权") {
                    if !granted { request() }
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                    refresh()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() {
        accessibilityGranted = AccessibilityAuthorization.isTrusted
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }
}
