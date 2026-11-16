import Foundation

enum AppCommand: Codable, Hashable, Identifiable, Sendable {
    case toggleLastFeaturePanel
    case showFeaturePanel(FeaturePanelKind)
    case windowControl(WindowControlID)
    case composedWindowControl(ComposedWindowControlID)

    var id: String {
        switch self {
        case .toggleLastFeaturePanel:
            "panel.toggleLast"
        case let .showFeaturePanel(panel):
            "panel.show.\(panel.rawValue)"
        case let .windowControl(control):
            "window.\(control.rawValue)"
        case let .composedWindowControl(control):
            "composed.\(control.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .toggleLastFeaturePanel:
            "打开上次使用的面板"
        case .showFeaturePanel(.encodingConversion):
            "打开编码与转换"
        case .showFeaturePanel(.safariWindows):
            "打开 Safari 窗口"
        case let .windowControl(control):
            WindowControlCatalog.descriptors.first(where: { $0.id == control })?.title
                ?? control.rawValue
        case let .composedWindowControl(control):
            ComposedWindowControlCatalog.descriptor(for: control)?.title ?? control.rawValue
        }
    }

    var subtitle: String {
        switch self {
        case .toggleLastFeaturePanel:
            "再次触发时关闭面板"
        case .showFeaturePanel:
            "直接显示指定面板"
        case let .windowControl(control):
            WindowControlCatalog.descriptors.first(where: { $0.id == control })?.subtitle ?? ""
        case let .composedWindowControl(control):
            ComposedWindowControlCatalog.sizeTarget(for: control, press: .short)?.title
                ?? ComposedWindowControlCatalog.descriptor(for: control)?.subtitle ?? ""
        }
    }

    var systemImage: String {
        switch self {
        case .toggleLastFeaturePanel:
            "hammer"
        case .showFeaturePanel(.encodingConversion):
            "curlybraces"
        case .showFeaturePanel(.safariWindows):
            "safari"
        case .windowControl(.movePointerToNextScreen):
            "cursorarrow.motionlines"
        case .windowControl(.moveWindowToNextScreen):
            "rectangle.portrait.and.arrow.forward"
        case .composedWindowControl(.centerPlacement):
            "rectangle.center.inset.filled"
        case .composedWindowControl:
            "macwindow"
        }
    }
}

struct AppCommandSection: Identifiable, Sendable {
    let id: String
    let title: String
    let commands: [AppCommand]
}

enum AppCommandCatalog {
    static let sections: [AppCommandSection] = [
        AppCommandSection(
            id: "panels",
            title: "工具面板",
            commands: [
                .toggleLastFeaturePanel,
                .showFeaturePanel(.encodingConversion),
                .showFeaturePanel(.safariWindows)
            ]
        ),
        AppCommandSection(
            id: "window-layout",
            title: "窗口布局",
            commands: ComposedWindowControlCatalog.descriptors.map {
                AppCommand.composedWindowControl($0.id)
            }
        ),
        AppCommandSection(
            id: "cross-screen",
            title: "跨屏移动",
            commands: WindowControlCatalog.crossScreenIDs.map(AppCommand.windowControl)
        )
    ]
}
