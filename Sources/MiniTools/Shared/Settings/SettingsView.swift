import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case windowManagement
    case closedLidRunning
    case dsStoreManagement
    case mouseBindings
    case cursorAnimation
    case usageStatistics

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "通用"
        case .windowManagement: "窗口管理"
        case .closedLidRunning: "合盖运行"
        case .dsStoreManagement: "DS_Store 管理"
        case .mouseBindings: "鼠标侧键"
        case .cursorAnimation: "定位动画"
        case .usageStatistics: "使用统计"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            "配置应用启动、工具面板与转换参数。"
        case .windowManagement:
            "配置窗口布局、跨屏操作与全局快捷键。"
        case .closedLidRunning:
            "控制合盖运行并查看后台组件与系统状态。"
        case .dsStoreManagement:
            "清理磁盘中的 .DS_Store，并按需持续监控。"
        case .mouseBindings:
            "为 Button 4、Button 5 分配点击和方向拖动动作。"
        case .cursorAnimation:
            "一次查看并选择鼠标定位时轮换播放的视觉效果。"
        case .usageStatistics:
            "查看本机记录的成功操作次数。"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .windowManagement: "macwindow"
        case .closedLidRunning: "laptopcomputer"
        case .dsStoreManagement: "doc.badge.gearshape"
        case .mouseBindings: "computermouse"
        case .cursorAnimation: "cursorarrow.rays"
        case .usageStatistics: "chart.bar"
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
                usageStatistics: context.usageStatistics
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
    @ObservedObject var usageStatistics: UsageStatisticsStore
    @State private var selectedCategory: SettingsCategory? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.title, systemImage: category.systemImage)
                    .tag(category)
                    .help(category.subtitle)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
        } detail: {
            SettingsCategoryDetail(
                category: selectedCategory ?? .general,
                settings: settings,
                shortcutCoordinator: shortcutCoordinator,
                mouseBindingCoordinator: mouseBindingCoordinator,
                closedLidRunningController: closedLidRunningController,
                dsStoreManagementController: dsStoreManagementController,
                usageStatistics: usageStatistics
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
    @ObservedObject var usageStatistics: UsageStatisticsStore
    @State private var confirmsStatisticsClear = false

    var body: some View {
        Form {
            switch category {
            case .general:
                generalSettings
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
                Section {
                    CursorAnimationSettingsView(settings: settings)
                } footer: {
                    Text("可以全部关闭；启用多个时，每次定位会依次轮换。")
                }
            case .usageStatistics:
                usageStatisticsSettings
            }
        }
        .formStyle(.grouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(category.title)
        .alert("清除使用统计？", isPresented: $confirmsStatisticsClear) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                usageStatistics.clear()
            }
        } message: {
            Text("此操作只清除本机统计，无法撤销。")
        }
    }

    @ViewBuilder
    private var generalSettings: some View {
        Section("应用") {
            Toggle(
                "登录时启动 miniTools",
                isOn: Binding(
                    get: { settings.launchAtLoginEnabled },
                    set: { dsStoreManagementController.setLaunchAtLoginEnabled($0) }
                )
            )
            if dsStoreManagementController.loginItemState == .requiresApproval {
                LabeledContent("登录项") {
                    Button("前往批准") {
                        dsStoreManagementController.openLoginItemSettings()
                    }
                }
            }
        }

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
                "使用 macOS 原生窗口布局",
                isOn: Binding(
                    get: { settings.usesSystemWindowActions },
                    set: { settings.updateUsesSystemWindowActions($0) }
                )
            )
        } footer: {
            Text("支持时使用 macOS 原生布局和跨屏操作，否则自动使用 miniTools。成功后会在屏幕右上角显示实际采用的方式。")
        }

        Section("四角") {
            ForEach(windowDescriptors([.upperLeft, .upperRight, .lowerLeft, .lowerRight])) { descriptor in
                windowControlRow(descriptor)
            }
        }

        Section("边缘与尺寸") {
            ForEach(windowDescriptors([.left, .right, .horizontalHalves, .verticalThirds])) { descriptor in
                windowControlRow(descriptor)
            }
        }

        Section("其他") {
            ForEach(windowDescriptors([.maximize, .centerWindow])) { descriptor in
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
            HStack {
                Text("快捷键修改后立即生效。窗口操作需要辅助功能权限。")
                Spacer()
                Button("恢复默认快捷键") {
                    shortcutCoordinator.restoreDefaultWindowControlShortcuts()
                }
            }
        }
    }

    @ViewBuilder
    private var closedLidRunningSettings: some View {
        Section {
            Toggle(
                "启用合盖运行",
                isOn: Binding(
                    get: { closedLidRunningController.isFeatureEnabled },
                    set: { enabled in
                        if enabled {
                            closedLidRunningController.enable()
                        } else {
                            closedLidRunningController.disable()
                        }
                    }
                )
            )
            .disabled(closedLidRunningController.isBusy)

            LabeledContent {
                helperStatusControl
                    .frame(width: 190, alignment: .trailing)
            } label: {
                settingsLabel(
                    title: "后台组件",
                    subtitle: "用于控制 MacBook 合盖后的系统睡眠"
                )
            }
            LabeledContent {
                Text(systemSleepStateTitle)
                    .foregroundStyle(.secondary)
            } label: {
                settingsLabel(
                    title: "当前系统状态",
                    subtitle: "状态栏锤子旁的小点表示正在阻止睡眠"
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
            HStack {
                Text("清理磁盘中的 .DS_Store")
                    .foregroundStyle(.secondary)
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
            Text("功能")
        } footer: {
            Text("默认关闭。监控和立即清理都从 / 开始，并跳过废纸篓、系统目录、应用包、符号链接和无法读取的目录。")
        }

        if let error = dsStoreManagementController.lastError {
            Section("最近一次错误") {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var usageStatisticsSettings: some View {
        Section("概览") {
            LabeledContent("最近 7 天") {
                Text("\(usageStatistics.totalCount(recentDays: 7)) 次")
                    .monospacedDigit()
            }
            LabeledContent("最近 30 天") {
                Text("\(usageStatistics.totalCount(recentDays: 30)) 次")
                    .monospacedDigit()
            }
            LabeledContent("累计") {
                Text("\(usageStatistics.totalCount()) 次")
                    .monospacedDigit()
            }
            LabeledContent("开始统计") {
                Text(usageStatistics.startedAt.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened)
                ))
                .foregroundStyle(.secondary)
            }
        }

        ForEach(UsageStatisticsCategory.allCases) { category in
            Section(category.title) {
                let records = usageStatistics.records(in: category)
                if records.isEmpty {
                    Text("暂无使用记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records) { record in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("近 30 天 \(usageStatistics.count(for: record, recentDays: 30)) 次")
                                    .monospacedDigit()
                                Text("累计 \(record.totalCount) 次")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } label: {
                            settingsLabel(
                                title: record.title,
                                subtitle: "最近使用：\(record.lastUsedAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                        }
                    }
                }
            }
        }

        Section {
            Button("清除使用统计…", role: .destructive) {
                confirmsStatisticsClear = true
            }
            .disabled(usageStatistics.records.isEmpty)
        } footer: {
            Text("仅保存在这台 Mac 上。只统计成功完成的编码与转换、窗口管理和鼠标跨屏操作，不记录处理内容、窗口标题或文件信息。")
        }
    }

    private var systemSleepStateTitle: String {
        switch closedLidRunningController.actualSleepDisabled {
        case true: "阻止睡眠（SleepDisabled = 1）"
        case false: "允许睡眠（SleepDisabled = 0）"
        case nil: "未知"
        }
    }

    private func windowDescriptors(
        _ ids: [WindowControlID]
    ) -> [WindowControlDescriptor] {
        ids.compactMap { id in
            WindowControlCatalog.descriptors.first(where: { $0.id == id })
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
