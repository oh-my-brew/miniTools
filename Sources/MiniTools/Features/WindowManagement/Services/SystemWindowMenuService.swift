import AppKit
import ApplicationServices
import Foundation

enum SystemWindowLayoutAction: Equatable, Sendable {
    case fill
    case center
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var accessibilityIdentifier: String {
        switch self {
        case .fill: "_zoomFill:"
        case .center: "_zoomCenter:"
        case .left: "_zoomLeft:"
        case .right: "_zoomRight:"
        case .top: "_zoomTop:"
        case .bottom: "_zoomBottom:"
        case .topLeft: "_zoomTopLeft:"
        case .topRight: "_zoomTopRight:"
        case .bottomLeft: "_zoomBottomLeft:"
        case .bottomRight: "_zoomBottomRight:"
        }
    }
}

enum SystemWindowActionResolver {
    static func layoutAction(
        for id: WindowControlID,
        candidateIndex: Int
    ) -> SystemWindowLayoutAction? {
        switch (id, candidateIndex) {
        case (.upperLeft, 0): .topLeft
        case (.upperRight, 0): .topRight
        case (.lowerLeft, 0): .bottomLeft
        case (.lowerRight, 0): .bottomRight
        case (.left, 1): .left
        case (.right, 1): .right
        case (.horizontalHalves, 0): .top
        case (.horizontalHalves, 1): .bottom
        case (.maximize, _): .fill
        default: nil
        }
    }
}

enum SystemWindowMenuService {
    private static let maximumInspectedElementCount = 800
    private static let menuItemRole = kAXMenuItemRole as String

    static func performLayoutAction(
        _ action: SystemWindowLayoutAction,
        processIdentifier: pid_t
    ) -> Bool {
        performMenuItem(
            processIdentifier: processIdentifier,
            identifiers: [action.accessibilityIdentifier],
            titles: []
        )
    }

    static func performCenterAction(processIdentifier: pid_t) -> Bool {
        performLayoutAction(.center, processIdentifier: processIdentifier)
    }

    static func performMoveAction(
        to displayName: String,
        destinationIsBuiltIn: Bool,
        processIdentifier: pid_t
    ) -> Bool {
        var titles = moveToDisplayTitles(displayName: displayName)
        if destinationIsBuiltIn {
            titles.formUnion(moveBackToMacTitles())
        }
        return performMenuItem(
            processIdentifier: processIdentifier,
            identifiers: [],
            titles: titles
        )
    }

    static func moveToDisplayTitles(displayName: String) -> Set<String> {
        let localizedFormat = appKitString("Move to %@")
        return unique([
            String(format: localizedFormat, displayName),
            String(format: "Move to “%@”", displayName),
            String(format: "Move to \"%@\"", displayName)
        ])
    }

    static func moveBackToMacTitles() -> Set<String> {
        unique([
            appKitString("Move Window Back to Mac"),
            "Move Window Back to Mac"
        ])
    }

    private static func performMenuItem(
        processIdentifier: pid_t,
        identifiers: Set<String>,
        titles: Set<String>
    ) -> Bool {
        let application = AccessibilityClient.application(for: processIdentifier)
        guard let menuBar = AccessibilityClient.element(
            from: application,
            attribute: kAXMenuBarAttribute as CFString
        ) else {
            return false
        }

        var queue = AccessibilityClient.elements(
            from: menuBar,
            attribute: kAXChildrenAttribute as CFString
        )
        var cursor = 0
        var inspectedElementCount = 0

        while cursor < queue.count, inspectedElementCount < maximumInspectedElementCount {
            let element = queue[cursor]
            cursor += 1
            inspectedElementCount += 1

            let role = AccessibilityClient.string(
                from: element,
                attribute: kAXRoleAttribute as CFString
            )
            if role == menuItemRole,
               AccessibilityClient.boolean(
                   from: element,
                   attribute: kAXEnabledAttribute as CFString
               ) != false {
                let identifier = AccessibilityClient.string(
                    from: element,
                    attribute: kAXIdentifierAttribute as CFString
                )
                let title = AccessibilityClient.string(
                    from: element,
                    attribute: kAXTitleAttribute as CFString
                )
                if identifier.map(identifiers.contains) == true
                    || title.map(titles.contains) == true {
                    return AccessibilityClient.perform(
                        kAXPressAction as CFString,
                        on: element
                    ) == .success
                }
            }

            queue.append(contentsOf: AccessibilityClient.elements(
                from: element,
                attribute: kAXChildrenAttribute as CFString
            ))
        }
        return false
    }

    private static func appKitString(_ key: String) -> String {
        Bundle(for: NSApplication.self).localizedString(
            forKey: key,
            value: key,
            table: "MenuCommands"
        )
    }

    private static func unique(_ values: [String]) -> Set<String> {
        Set(values.filter { !$0.isEmpty })
    }
}
