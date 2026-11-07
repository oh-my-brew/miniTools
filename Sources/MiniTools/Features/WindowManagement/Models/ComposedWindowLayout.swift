import Carbon
import CoreGraphics

enum WindowManagementMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic
    case sizeAndPosition

    var id: Self { self }

    var title: String {
        switch self {
        case .classic: "经典布局"
        case .sizeAndPosition: "尺寸与位置"
        }
    }
}

enum ComposedWindowControlID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fullOrHalfHeight
    case twoThirdsWidth
    case halfOrThirdFullHeight
    case halfOrThirdHalfHeight
    case leadingPlacement
    case trailingPlacement
    case centerPlacement

    var id: Self { self }
}

enum WindowShortcutPress: Sendable {
    case short
    case long
}

enum ComposedWindowPlacement: Sendable {
    case leading
    case trailing
    case center
}

struct ComposedWindowControlDescriptor: Identifiable, Sendable {
    let id: ComposedWindowControlID
    let title: String
    let subtitle: String
    let defaultShortcut: KeyboardShortcut
    let supportsLongPress: Bool
}

struct ComposedWindowSizeTarget: Sendable {
    let frame: UnitWindowFrame
    let statisticsID: String
    let title: String
}

struct ComposedWindowPlacementTarget: Equatable, Sendable {
    let frame: CGRect
    let statisticsID: String
    let title: String
}

enum ComposedWindowControlCatalog {
    private static let defaultModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    static let descriptors: [ComposedWindowControlDescriptor] = [
        descriptor(
            .fullOrHalfHeight,
            "全宽",
            "短按：全屏 · 长按：上半屏",
            kVK_ANSI_U,
            supportsLongPress: true
        ),
        descriptor(
            .twoThirdsWidth,
            "三分之二宽",
            "满高并居中",
            kVK_ANSI_I
        ),
        descriptor(
            .halfOrThirdFullHeight,
            "满高窄窗",
            "短按：二分之一宽 · 长按：三分之一宽",
            kVK_ANSI_J,
            supportsLongPress: true
        ),
        descriptor(
            .halfOrThirdHalfHeight,
            "半高窄窗",
            "短按：二分之一宽 · 长按：三分之一宽",
            kVK_ANSI_K,
            supportsLongPress: true
        ),
        descriptor(
            .leadingPlacement,
            "向前侧定位",
            "左侧；半高布局在左上与左下之间切换",
            kVK_ANSI_H
        ),
        descriptor(
            .trailingPlacement,
            "向后侧定位",
            "右侧；半高布局在右上与右下之间切换",
            kVK_ANSI_L
        ),
        descriptor(
            .centerPlacement,
            "窗口居中",
            "保持当前尺寸；全宽布局不移动",
            kVK_Return
        )
    ]

    static let sizeIDs: [ComposedWindowControlID] = [
        .fullOrHalfHeight,
        .twoThirdsWidth,
        .halfOrThirdFullHeight,
        .halfOrThirdHalfHeight
    ]

    static let placementIDs: [ComposedWindowControlID] = [
        .leadingPlacement,
        .trailingPlacement,
        .centerPlacement
    ]

    static var defaultShortcuts: [ComposedWindowControlID: KeyboardShortcut] {
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0.defaultShortcut) })
    }

    static func descriptor(for id: ComposedWindowControlID) -> ComposedWindowControlDescriptor? {
        descriptors.first(where: { $0.id == id })
    }

    static func sizeTarget(
        for id: ComposedWindowControlID,
        press: WindowShortcutPress
    ) -> ComposedWindowSizeTarget? {
        switch (id, press) {
        case (.fullOrHalfHeight, .short):
            ComposedWindowSizeTarget(
                frame: UnitWindowFrame(0, 0, 1, 1),
                statisticsID: "size.full",
                title: "全屏"
            )
        case (.fullOrHalfHeight, .long):
            ComposedWindowSizeTarget(
                frame: UnitWindowFrame(0, 0, 1, 0.5),
                statisticsID: "size.fullWidthHalfHeight",
                title: "全宽半高 · 上半屏"
            )
        case (.twoThirdsWidth, _):
            ComposedWindowSizeTarget(
                frame: UnitWindowFrame(1.0 / 6.0, 0, 2.0 / 3.0, 1),
                statisticsID: "size.twoThirdsFullHeight",
                title: "三分之二宽 · 满高居中"
            )
        case (.halfOrThirdFullHeight, .short):
            ComposedWindowSizeTarget(
                frame: UnitWindowFrame(0.25, 0, 0.5, 1),
                statisticsID: "size.halfFullHeight",
                title: "二分之一宽 · 满高居中"
            )
        case (.halfOrThirdFullHeight, .long):
            ComposedWindowSizeTarget(
                frame: UnitWindowFrame(1.0 / 3.0, 0, 1.0 / 3.0, 1),
                statisticsID: "size.thirdFullHeight",
                title: "三分之一宽 · 满高居中"
            )
        case (.halfOrThirdHalfHeight, .short):
            ComposedWindowSizeTarget(
                frame: UnitWindowFrame(0.25, 0.25, 0.5, 0.5),
                statisticsID: "size.halfHalfHeight",
                title: "二分之一宽 · 半高居中"
            )
        case (.halfOrThirdHalfHeight, .long):
            ComposedWindowSizeTarget(
                frame: UnitWindowFrame(1.0 / 3.0, 0.25, 1.0 / 3.0, 0.5),
                statisticsID: "size.thirdHalfHeight",
                title: "三分之一宽 · 半高居中"
            )
        default:
            nil
        }
    }

    static func placement(for id: ComposedWindowControlID) -> ComposedWindowPlacement? {
        switch id {
        case .leadingPlacement: .leading
        case .trailingPlacement: .trailing
        case .centerPlacement: .center
        default: nil
        }
    }

    private static func descriptor(
        _ id: ComposedWindowControlID,
        _ title: String,
        _ subtitle: String,
        _ keyCode: Int,
        supportsLongPress: Bool = false
    ) -> ComposedWindowControlDescriptor {
        ComposedWindowControlDescriptor(
            id: id,
            title: title,
            subtitle: subtitle,
            defaultShortcut: KeyboardShortcut(
                keyCode: UInt32(keyCode),
                carbonModifiers: defaultModifiers
            ),
            supportsLongPress: supportsLongPress
        )
    }
}
