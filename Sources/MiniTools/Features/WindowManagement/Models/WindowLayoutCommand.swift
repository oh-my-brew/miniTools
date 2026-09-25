import Carbon
import CoreGraphics

struct UnitWindowFrame: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

enum WindowControlID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case upperLeft
    case upperRight
    case lowerLeft
    case lowerRight
    case left
    case right
    case horizontalHalves
    case verticalThirds
    case maximize
    case moveWindowToNextScreen
    case movePointerToNextScreen
    case centerWindow

    var id: Self { self }
}

struct WindowLayoutCommand: Identifiable, Sendable {
    let id: WindowControlID
    let frames: [UnitWindowFrame]

    /// 每个候选尺寸对应的展示名称，用于使用统计与结果提示。
    let targetTitles: [String]

    init(
        id: WindowControlID,
        frames: [UnitWindowFrame],
        targetTitles: [String]
    ) {
        precondition(
            frames.count == targetTitles.count,
            "\(id.rawValue) 的候选尺寸与名称数量不一致"
        )
        self.id = id
        self.frames = frames
        self.targetTitles = targetTitles
    }

    /// 同一次快捷键会在这些候选之间循环；尺寸完全相同时不算循环。
    var cyclesThroughTargets: Bool {
        guard frames.count > 1, let first = frames.first else { return false }
        return frames.dropFirst().contains { $0 != first }
    }
}

struct WindowControlDescriptor: Identifiable, Sendable {
    let id: WindowControlID
    let title: String
    let subtitle: String
    let defaultShortcut: KeyboardShortcut
}

enum WindowControlCatalog {
    static let defaultModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    static let layoutCommands: [WindowLayoutCommand] = [
        .init(
            id: .upperLeft,
            frames: [.init(0, 0, 0.5, 0.5), .init(0, 0, 1.0 / 3.0, 0.5)],
            targetTitles: ["左上区域 · 半宽", "左上区域 · 三分之一宽"]
        ),
        .init(
            id: .upperRight,
            frames: [.init(0.5, 0, 0.5, 0.5), .init(2.0 / 3.0, 0, 1.0 / 3.0, 0.5)],
            targetTitles: ["右上区域 · 半宽", "右上区域 · 三分之一宽"]
        ),
        .init(
            id: .lowerLeft,
            frames: [.init(0, 0.5, 0.5, 0.5), .init(0, 0.5, 1.0 / 3.0, 0.5)],
            targetTitles: ["左下区域 · 半宽", "左下区域 · 三分之一宽"]
        ),
        .init(
            id: .lowerRight,
            frames: [.init(0.5, 0.5, 0.5, 0.5), .init(2.0 / 3.0, 0.5, 1.0 / 3.0, 0.5)],
            targetTitles: ["右下区域 · 半宽", "右下区域 · 三分之一宽"]
        ),
        .init(
            id: .left,
            frames: [.init(0, 0, 0.5, 1), .init(0, 0, 2.0 / 3.0, 1)],
            targetTitles: ["左侧区域 · 二分之一宽", "左侧区域 · 三分之二宽"]
        ),
        .init(
            id: .right,
            frames: [.init(0.5, 0, 0.5, 1), .init(1.0 / 3.0, 0, 2.0 / 3.0, 1)],
            targetTitles: ["右侧区域 · 二分之一宽", "右侧区域 · 三分之二宽"]
        ),
        .init(
            id: .horizontalHalves,
            frames: [.init(0, 0, 1, 0.5), .init(0, 0.5, 1, 0.5)],
            targetTitles: ["上半屏", "下半屏"]
        ),
        .init(
            id: .verticalThirds,
            frames: [.init(2.0 / 3.0, 0, 1.0 / 3.0, 1), .init(0, 0, 1.0 / 3.0, 1)],
            targetTitles: ["右侧三分之一", "左侧三分之一"]
        ),
        .init(
            id: .maximize,
            frames: [.init(0, 0, 1, 1), .init(0, 0, 1, 1)],
            targetTitles: ["铺满当前屏幕", "铺满当前屏幕"]
        )
    ]

    static let descriptors: [WindowControlDescriptor] = [
        descriptor(.upperLeft, "左上区域", "半宽 ↔ 三分之一宽", kVK_ANSI_U),
        descriptor(.upperRight, "右上区域", "半宽 ↔ 三分之一宽", kVK_ANSI_I),
        descriptor(.lowerLeft, "左下区域", "半宽 ↔ 三分之一宽", kVK_ANSI_J),
        descriptor(.lowerRight, "右下区域", "半宽 ↔ 三分之一宽", kVK_ANSI_K),
        descriptor(.left, "左侧区域", "二分之一 ↔ 三分之二宽", kVK_ANSI_H),
        descriptor(.right, "右侧区域", "二分之一 ↔ 三分之二宽", kVK_ANSI_L),
        descriptor(.horizontalHalves, "上下半屏切换", "上半屏 ↔ 下半屏", kVK_ANSI_Y),
        descriptor(.verticalThirds, "左右三分之一切换", "右侧三分之一 ↔ 左侧三分之一", kVK_ANSI_O),
        descriptor(.maximize, "铺满当前屏幕", "使用屏幕可用区域", kVK_ANSI_Backslash),
        descriptor(.centerWindow, "窗口居中", "保持窗口当前尺寸", kVK_Return),
        descriptor(.moveWindowToNextScreen, "窗口移至下一屏", "保留窗口相对位置", kVK_ANSI_P),
        descriptor(.movePointerToNextScreen, "鼠标移至下一屏", "移动后显示定位动画", kVK_ANSI_Semicolon)
    ]

    static let windowLayoutIDs: [WindowControlID] = [
        .upperLeft, .upperRight, .lowerLeft, .lowerRight,
        .left, .right, .horizontalHalves, .verticalThirds,
        .maximize, .centerWindow
    ]

    static let crossScreenIDs: [WindowControlID] = [
        .moveWindowToNextScreen, .movePointerToNextScreen
    ]

    static var windowLayoutDescriptors: [WindowControlDescriptor] {
        descriptors(for: windowLayoutIDs)
    }

    static var crossScreenDescriptors: [WindowControlDescriptor] {
        descriptors(for: crossScreenIDs)
    }

    static var defaultShortcuts: [WindowControlID: KeyboardShortcut] {
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0.defaultShortcut) })
    }

    static func layoutCommand(for id: WindowControlID) -> WindowLayoutCommand? {
        layoutCommands.first(where: { $0.id == id })
    }

    /// 使用统计与结果提示使用的名称；循环命令细化到具体尺寸。
    static func targetTitle(for id: WindowControlID, candidateIndex: Int) -> String {
        let fallback = descriptors.first(where: { $0.id == id })?.title ?? "窗口操作"
        guard
            let command = layoutCommand(for: id),
            command.cyclesThroughTargets,
            command.targetTitles.indices.contains(candidateIndex)
        else {
            return fallback
        }
        return command.targetTitles[candidateIndex]
    }

    /// 循环命令按具体尺寸分别统计，其余命令维持单一记录。
    static func statisticsID(for id: WindowControlID, candidateIndex: Int) -> String {
        guard let command = layoutCommand(for: id), command.cyclesThroughTargets else {
            return id.rawValue
        }
        return "\(id.rawValue).\(candidateIndex)"
    }

    private static func descriptors(
        for ids: [WindowControlID]
    ) -> [WindowControlDescriptor] {
        ids.compactMap { id in descriptors.first(where: { $0.id == id }) }
    }

    private static func descriptor(
        _ id: WindowControlID,
        _ title: String,
        _ subtitle: String,
        _ keyCode: Int
    ) -> WindowControlDescriptor {
        WindowControlDescriptor(
            id: id,
            title: title,
            subtitle: subtitle,
            defaultShortcut: KeyboardShortcut(
                keyCode: UInt32(keyCode),
                carbonModifiers: defaultModifiers
            )
        )
    }
}
