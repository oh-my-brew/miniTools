import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case featurePanel
    case windowManagement
    case closedLidRunning
    case dsStoreManagement
    case mouseBindings
    case cursorAnimation

    var id: Self { self }

    var title: String {
        switch self {
        case .featurePanel: "工具面板"
        case .windowManagement: "窗口管理"
        case .closedLidRunning: "合盖运行"
        case .dsStoreManagement: "DS_Store 管理"
        case .mouseBindings: "鼠标侧键"
        case .cursorAnimation: "定位动画"
        }
    }

    var subtitle: String {
        switch self {
        case .featurePanel:
            "配置统一面板的唤起方式与转换参数。"
        case .windowManagement:
            "配置窗口布局、跨屏操作与全局快捷键。"
        case .closedLidRunning:
            "查看合盖运行服务状态与最近关闭记录。"
        case .dsStoreManagement:
            "清理磁盘中的 .DS_Store，并按需持续监控。"
        case .mouseBindings:
            "为 Button 4、Button 5 分配点击和方向拖动动作。"
        case .cursorAnimation:
            "选择鼠标定位时轮换播放的视觉效果。"
        }
    }

    var systemImage: String {
        switch self {
        case .featurePanel: "hammer"
        case .windowManagement: "macwindow"
        case .closedLidRunning: "laptopcomputer"
        case .dsStoreManagement: "doc.badge.gearshape"
        case .mouseBindings: "computermouse"
        case .cursorAnimation: "cursorarrow.rays"
        }
    }
}

struct SettingsSceneRoot: View {
    @ObservedObject var context: ApplicationContext

    var body: some View {
        if let shortcutCoordinator = context.shortcutCoordinator,
           let mouseBindingCoordinator = context.mouseBindingCoordinator,
           let closedLidRunningController = context.closedLidRunningController,
           let dsStoreManagementController = context.dsStoreManagementController {
            SettingsView(
                settings: context.settings,
                shortcutCoordinator: shortcutCoordinator,
                mouseBindingCoordinator: mouseBindingCoordinator,
                closedLidRunningController: closedLidRunningController,
                dsStoreManagementController: dsStoreManagementController,
                previewCursorHighlight: context.previewCursorHighlight
            )
        } else {
            ProgressView("正在载入设置…")
                .frame(minWidth: 760, minHeight: 520)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shortcutCoordinator: GlobalShortcutCoordinator
    @ObservedObject var mouseBindingCoordinator: MouseBindingCoordinator
    @ObservedObject var closedLidRunningController: ClosedLidRunningController
    @ObservedObject var dsStoreManagementController: DSStoreManagementController
    let previewCursorHighlight: (CursorHighlightStyle) -> Void
    @State private var selectedCategory: SettingsCategory? = .featurePanel

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.title, systemImage: category.systemImage)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
        } detail: {
            SettingsCategoryDetail(
                category: selectedCategory ?? .featurePanel,
                settings: settings,
                shortcutCoordinator: shortcutCoordinator,
                mouseBindingCoordinator: mouseBindingCoordinator,
                closedLidRunningController: closedLidRunningController,
                dsStoreManagementController: dsStoreManagementController,
                previewCursorHighlight: previewCursorHighlight
            )
            .id(selectedCategory)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 540)
    }
}

private struct SettingsCategoryDetail: View {
    let category: SettingsCategory
    @ObservedObject var settings: AppSettings
    @ObservedObject var shortcutCoordinator: GlobalShortcutCoordinator
    @ObservedObject var mouseBindingCoordinator: MouseBindingCoordinator
    @ObservedObject var closedLidRunningController: ClosedLidRunningController
    @ObservedObject var dsStoreManagementController: DSStoreManagementController
    let previewCursorHighlight: (CursorHighlightStyle) -> Void
    @State private var showsCompactTitle = false

    var body: some View {
        Form {
            Section {
                categoryHeader
            }

            switch category {
            case .featurePanel:
                featurePanelSettings
            case .windowManagement:
                windowManagementSettings
            case .closedLidRunning:
                closedLidRunningSettings
            case .dsStoreManagement:
                dsStoreManagementSettings
            case .mouseBindings:
                MouseBindingSettingsView(
                    settings: settings,
                    coordinator: mouseBindingCoordinator
                )
            case .cursorAnimation:
                CursorAnimationSettingsView(
                    settings: settings,
                    preview: previewCursorHighlight
                )
            }
        }
        .formStyle(.grouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(showsCompactTitle ? category.title : "")
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 72
        } action: { _, isPastHeader in
            showsCompactTitle = isPastHeader
        }
    }

    private var categoryHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: category.systemImage)
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 68, height: 68)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 17, style: .continuous))

            Text(category.title)
                .font(.system(size: 26, weight: .bold))

            Text(category.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var featurePanelSettings: some View {
        Section("唤起") {
            panelShortcutRow
        }

        Section("图片处理") {
            LabeledContent {
                HStack(spacing: 10) {
                    Slider(value: $settings.compressionQuality, in: 0.4...0.95, step: 0.05)
                        .frame(width: 170)
                    Text("\(Int(settings.compressionQuality * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            } label: {
                settingsLabel(
                    title: "JPEG 压缩质量",
                    subtitle: "用于“压缩图片”操作；质量越高，文件通常越大"
                )
            }
        }
    }

    @ViewBuilder
    private var windowManagementSettings: some View {
        Section {
            Toggle(
                "优先使用系统窗口操作",
                isOn: Binding(
                    get: { settings.usesSystemWindowActions },
                    set: { settings.updateUsesSystemWindowActions($0) }
                )
            )
        } footer: {
            Text("开启后优先调用当前应用的系统窗口布局与跨屏菜单；应用不支持时自动使用 miniTools 原有方式。")
        }

        Section("窗口布局") {
            ForEach(WindowControlCatalog.windowLayoutDescriptors) { descriptor in
                windowControlRow(descriptor)
            }
        }

        Section {
            ForEach(WindowControlCatalog.crossScreenDescriptors) { descriptor in
                windowControlRow(descriptor)
            }
        } header: {
            Text("跨屏操作")
        } footer: {
            Text("快捷键修改后立即生效。窗口操作需要辅助功能权限。")
        }
    }

    @ViewBuilder
    private var closedLidRunningSettings: some View {
        Section {
            LabeledContent {
                helperStatusControl
                    .frame(width: 190, alignment: .trailing)
            } label: {
                settingsLabel(
                    title: "服务状态",
                    subtitle: "用于控制 MacBook 合盖后的系统睡眠"
                )
            }
            LabeledContent {
                Text(closedLidRunningController.actualStateTitle)
                    .foregroundStyle(.secondary)
            } label: {
                settingsLabel(
                    title: "SleepDisabled 实际值",
                    subtitle: "状态栏锤子旁的小点也显示这个值"
                )
            }
        } header: {
            Text("后台服务")
        } footer: {
            VStack(alignment: .leading, spacing: 5) {
                Text("每分钟检查电量；低于 20% 时关闭，高于 25% 时自动恢复。")
                if let error = closedLidRunningController.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }

        if !closedLidRunningController.recentClosedSessions.isEmpty {
            Section {
                ForEach(
                    Array(closedLidRunningController.recentClosedSessions.enumerated()),
                    id: \.offset
                ) { _, session in
                    LabeledContent {
                        if let stoppedAt = session.stoppedAt {
                            Text(stoppedAt.formatted(
                                Date.FormatStyle(date: .abbreviated, time: .shortened)
                            ))
                            .foregroundStyle(.secondary)
                        }
                    } label: {
                        settingsLabel(
                            title: session.stopReason?.title ?? "未知原因",
                            subtitle: "合盖运行会话"
                        )
                    }
                }
            } header: {
                Text("最近关闭")
            } footer: {
                Text("最多保留最近 5 次关闭时间与原因。")
            }
        }
    }

    @ViewBuilder
    private var helperStatusControl: some View {
        switch closedLidRunningController.helperState {
        case .enabled:
            Label("已启用", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .awaitingApproval:
            Button("前往批准") {
                closedLidRunningController.openHelperApproval()
            }
        case .notEnabled:
            Button("启用") {
                closedLidRunningController.enableHelper()
            }
        case .unavailable, .missing:
            Text(closedLidRunningController.helperState.title)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dsStoreManagementSettings: some View {
        Section {
            Toggle(
                "启用 DS_Store 管理",
                isOn: Binding(
                    get: { settings.dsStoreManagementEnabled },
                    set: { dsStoreManagementController.setFeatureEnabled($0) }
                )
            )
            LabeledContent("监控状态") {
                Text(dsStoreManagementController.isMonitoring ? "正在监控" : "未监控")
                    .foregroundStyle(
                        dsStoreManagementController.isMonitoring
                            ? Color.green
                            : Color.secondary
                    )
            }
            LabeledContent("本次删除") {
                Text("\(dsStoreManagementController.deletedCount) 个")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("功能")
        } footer: {
            Text("默认关闭。开启后使用 FSEvents 监听磁盘根目录。")
        }

        Section {
            HStack {
                LabeledContent("清理范围") {
                    Text("磁盘根目录（/）")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("立即清理") {
                    dsStoreManagementController.cleanNow()
                }
                .disabled(dsStoreManagementController.isCleaning)
                if dsStoreManagementController.isCleaning {
                    ProgressView().controlSize(.small)
                }
            }
        } header: {
            Text("目录")
        } footer: {
            Text("清理会从 / 开始递归，并跳过废纸篓、系统目录、应用包、符号链接和无法读取的目录。")
        }

        Section {
            Toggle(
                "登录时启动 miniTools",
                isOn: Binding(
                    get: { settings.launchAtLoginEnabled },
                    set: { dsStoreManagementController.setLaunchAtLoginEnabled($0) }
                )
            )
            LabeledContent("登录项状态") {
                HStack {
                    Text(dsStoreManagementController.loginItemState.title)
                        .foregroundStyle(.secondary)
                    if dsStoreManagementController.loginItemState == .requiresApproval {
                        Button("前往批准") {
                            dsStoreManagementController.openLoginItemSettings()
                        }
                    }
                }
            }
        } header: {
            Text("持续运行")
        } footer: {
            Text("登录启动作用于整个 miniTools；启用 DS_Store 管理后，应用运行期间持续监控磁盘。")
        }

        if let error = dsStoreManagementController.lastError {
            Section("最近一次错误") {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }

    private func shortcutRow(
        title: String,
        subtitle: String,
        shortcut: KeyboardShortcut,
        error: String?,
        onChange: @escaping (KeyboardShortcut) -> Bool
    ) -> some View {
        LabeledContent {
            ShortcutRecorderView(shortcut: shortcut, onChange: onChange)
                .frame(width: 190, height: 28)
        } label: {
            settingsLabel(title: title, subtitle: subtitle, error: error)
        }
    }

    private var panelShortcutRow: some View {
        shortcutRow(
            title: "全局快捷键",
            subtitle: "打开上次使用的面板",
            shortcut: settings.panelShortcut,
            error: shortcutCoordinator.panelError,
            onChange: shortcutCoordinator.updatePanelShortcut
        )
    }

    private func windowControlRow(_ descriptor: WindowControlDescriptor) -> some View {
        LabeledContent {
            ShortcutRecorderView(
                shortcut: settings.windowControlShortcut(for: descriptor.id),
                onChange: { shortcut in
                    shortcutCoordinator.updateWindowControlShortcut(shortcut, for: descriptor.id)
                }
            )
            .frame(width: 190, height: 28)
        } label: {
            settingsLabel(
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                error: shortcutCoordinator.windowControlErrors[descriptor.id]
            )
        }
    }

    private func settingsLabel(
        title: String,
        subtitle: String,
        error: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }
}
