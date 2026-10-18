import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case clipboardHistory
    case defaultApplications
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
        case .clipboardHistory: "剪贴板历史"
        case .defaultApplications: "默认应用"
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
        case .clipboardHistory:
            "配置本机剪贴板历史、保留期限和唤起快捷键。"
        case .defaultApplications:
            "查看文本与代码文件的当前默认应用，并按需改为 Sublime Text。"
        case .windowManagement:
            "配置窗口布局、跨屏操作与全局快捷键。"
        case .closedLidRunning:
            "控制合盖运行、防发热保护并查看系统状态。"
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
        case .clipboardHistory: "clipboard"
        case .defaultApplications: "doc.text"
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
           let rustDeskXHeatProtectionController = context.rustDeskXHeatProtectionController,
           let dsStoreManagementController = context.dsStoreManagementController,
           let clipboardHistoryController = context.clipboardHistoryController {
            SettingsView(
                settings: context.settings,
                shortcutCoordinator: shortcutCoordinator,
                mouseBindingCoordinator: mouseBindingCoordinator,
                closedLidRunningController: closedLidRunningController,
                rustDeskXHeatProtectionController: rustDeskXHeatProtectionController,
                dsStoreManagementController: dsStoreManagementController,
                clipboardHistoryController: clipboardHistoryController,
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
    @ObservedObject var rustDeskXHeatProtectionController: RustDeskXHeatProtectionController
    @ObservedObject var dsStoreManagementController: DSStoreManagementController
    let clipboardHistoryController: ClipboardHistoryPanelController
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
                rustDeskXHeatProtectionController: rustDeskXHeatProtectionController,
                dsStoreManagementController: dsStoreManagementController,
                clipboardHistoryController: clipboardHistoryController,
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
    @ObservedObject var rustDeskXHeatProtectionController: RustDeskXHeatProtectionController
    @ObservedObject var dsStoreManagementController: DSStoreManagementController
    let clipboardHistoryController: ClipboardHistoryPanelController
    @ObservedObject var usageStatistics: UsageStatisticsStore
    @State private var confirmsStatisticsClear = false
    @State private var confirmsClipboardHistoryClear = false

    var body: some View {
        Form {
            switch category {
            case .general:
                generalSettings
            case .clipboardHistory:
                clipboardHistorySettings
            case .defaultApplications:
                DefaultApplicationSettingsView()
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
        .alert("清除全部剪贴板历史？", isPresented: $confirmsClipboardHistoryClear) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { try? await clipboardHistoryController.deleteAll() }
            }
        } message: {
            Text("所有记录只保存在本机；清除后无法恢复。")
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
    private var clipboardHistorySettings: some View {
        Section {
            Toggle(
                "记录剪贴板历史",
                isOn: Binding(
                    get: { settings.clipboardHistoryEnabled },
                    set: { clipboardHistoryController.setCaptureEnabled($0) }
                )
            )
            Picker(
                "保留历史",
                selection: Binding(
                    get: { settings.clipboardHistoryRetention },
                    set: { clipboardHistoryController.updateRetention($0) }
                )
            ) {
                ForEach(ClipboardHistoryRetention.allCases, id: \.self) { retention in
                    Text(retention.title).tag(retention)
                }
            }
            LabeledContent("清理") {
                Button("清除全部历史", role: .destructive) {
                    confirmsClipboardHistoryClear = true
                }
            }
        } header: {
            Text("记录")
        } footer: {
            Text("记录保存在本机。机密或临时剪贴板内容会自动跳过。")
        }

        Section("快捷键") {
            shortcutRow(
                title: "打开剪贴板历史",
                subtitle: "默认 ⌘⇧V；与其他应用冲突时可在这里修改",
                shortcut: settings.clipboardHistoryShortcut,
                error: shortcutCoordinator.clipboardHistoryError,
                onChange: shortcutCoordinator.updateClipboardHistoryShortcut
            )
        }
    }

    @ViewBuilder
    private var windowManagementSettings: some View {
        Section {
            Picker(
                "窗口布局方案",
                selection: Binding(
                    get: { settings.windowManagementMode.rawValue },
                    set: { rawValue in
                        guard let mode = WindowManagementMode(rawValue: rawValue) else { return }
                        shortcutCoordinator.updateWindowManagementMode(mode)
                    }
                )
            ) {
                Text(WindowManagementMode.classic.title)
                    .tag(WindowManagementMode.classic.rawValue)
                Text(WindowManagementMode.sizeAndPosition.title)
                    .tag(WindowManagementMode.sizeAndPosition.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        } header: {
            Text("布局方案")
        } footer: {
            Text("经典布局按区域直接调整；尺寸与位置方案先选择窗口大小，再用 H、L 或 Return 定位。")
        }

        if settings.windowManagementMode == .classic {
            Section("四角") {
                ForEach(
                    windowDescriptors([.upperLeft, .upperRight, .lowerLeft, .lowerRight])
                ) { descriptor in
                    windowControlRow(descriptor)
                }
            }

            Section("边缘与尺寸") {
                ForEach(
                    windowDescriptors([.left, .right, .horizontalHalves, .verticalThirds])
                ) { descriptor in
                    windowControlRow(descriptor)
                }
            }

            Section("其他") {
                ForEach(windowDescriptors([.maximize, .centerWindow])) { descriptor in
                    windowControlRow(descriptor)
                }
            }
        } else {
            Section("长按") {
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: {
                                    Double(settings.windowLongPressThresholdMilliseconds)
                                },
                                set: { value in
                                    shortcutCoordinator
                                        .updateWindowLongPressThresholdMilliseconds(Int(value))
                                }
                            ),
                            in: Double(HotKeyLongPressRecognizer.minimumThresholdMilliseconds)...Double(HotKeyLongPressRecognizer.maximumThresholdMilliseconds),
                            step: Double(HotKeyLongPressRecognizer.thresholdStepMilliseconds)
                        )
                        .frame(width: 170)
                        Text("\(settings.windowLongPressThresholdMilliseconds)ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                } label: {
                    settingsLabel(
                        title: "长按触发时间",
                        subtitle: "用于 U、J、K 的长按尺寸动作"
                    )
                }
            }

            Section("窗口尺寸") {
                ForEach(composedWindowDescriptors(ComposedWindowControlCatalog.sizeIDs)) {
                    descriptor in
                    composedWindowControlRow(descriptor)
                }
            }

            Section("窗口位置") {
                ForEach(composedWindowDescriptors(ComposedWindowControlCatalog.placementIDs)) {
                    descriptor in
                    composedWindowControlRow(descriptor)
                }
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
                Text(
                    settings.windowManagementMode == .sizeAndPosition
                        ? "长按时间和快捷键修改后立即生效；窗口操作需要辅助功能权限。"
                        : "快捷键修改后立即生效。窗口操作需要辅助功能权限。"
                )
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

        Section {
            Toggle(
                "合盖或锁屏时强制关闭 RustDeskX",
                isOn: Binding(
                    get: { rustDeskXHeatProtectionController.isEnabled },
                    set: { rustDeskXHeatProtectionController.setEnabled($0) }
                )
            )
        } header: {
            Text("防发热")
        } footer: {
            VStack(alignment: .leading, spacing: 5) {
                Text("默认关闭。开启后仅在合盖或锁屏事件发生时检查并强制关闭正在运行的 RustDeskX。")
                if let lastAction = rustDeskXHeatProtectionController.lastAction {
                    Label(lastAction, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let lastError = rustDeskXHeatProtectionController.lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
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

    private func composedWindowDescriptors(
        _ ids: [ComposedWindowControlID]
    ) -> [ComposedWindowControlDescriptor] {
        ids.compactMap { ComposedWindowControlCatalog.descriptor(for: $0) }
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

    private func composedWindowControlRow(
        _ descriptor: ComposedWindowControlDescriptor
    ) -> some View {
        LabeledContent {
            ShortcutRecorderView(
                shortcut: settings.composedWindowControlShortcut(for: descriptor.id),
                onChange: { shortcut in
                    shortcutCoordinator.updateComposedWindowControlShortcut(
                        shortcut,
                        for: descriptor.id
                    )
                }
            )
            .frame(width: 190, height: 28)
        } label: {
            settingsLabel(
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                error: shortcutCoordinator.composedWindowControlErrors[descriptor.id]
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
