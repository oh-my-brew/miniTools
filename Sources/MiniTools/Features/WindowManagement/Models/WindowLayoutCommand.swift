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
    case moveWindowToNextScreen
    case movePointerToNextScreen

    var id: Self { self }
}

struct WindowControlDescriptor: Identifiable, Sendable {
    let id: WindowControlID
    let title: String
    let subtitle: String
    let defaultShortcut: KeyboardShortcut
}

enum WindowControlCatalog {
    static let defaultModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    static let descriptors: [WindowControlDescriptor] = [
        descriptor(.moveWindowToNextScreen, "窗口移至下一屏", "保留窗口相对位置", kVK_ANSI_Semicolon),
        descriptor(.movePointerToNextScreen, "鼠标移至下一屏", "移动后显示定位动画", kVK_ANSI_Quote)
    ]

    static let crossScreenIDs: [WindowControlID] = [
        .moveWindowToNextScreen, .movePointerToNextScreen
    ]

    static var crossScreenDescriptors: [WindowControlDescriptor] {
        descriptors(for: crossScreenIDs)
    }

    static var defaultShortcuts: [WindowControlID: KeyboardShortcut] {
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0.defaultShortcut) })
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
