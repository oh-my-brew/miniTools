import ApplicationServices
import CoreGraphics
import Foundation

enum WindowAccessibilityHealth {
    static func isInvalid(
        candidateRoles: [String],
        hasVisibleWindow: Bool
    ) -> Bool {
        hasVisibleWindow
            && !candidateRoles.contains(kAXWindowRole as String)
    }
}

enum WindowTargetResolver {
    static func candidateProcessIdentifiers(
        accessibilityFocusedProcessIdentifier: pid_t?,
        frontmostProcessIdentifier: pid_t?,
        currentProcessIdentifier: pid_t
    ) -> [pid_t] {
        var candidates: [pid_t] = []
        for candidate in [
            accessibilityFocusedProcessIdentifier,
            frontmostProcessIdentifier
        ].compactMap({ $0 }) where
            candidate > 0
            && candidate != currentProcessIdentifier
            && !candidates.contains(candidate)
        {
            candidates.append(candidate)
        }
        return candidates
    }
}

enum WindowServerWindowInspector {
    static func hasVisibleWindow(processIdentifier: pid_t) -> Bool {
        frontmostVisibleWindowFrame(processIdentifier: processIdentifier) != nil
    }

    static func frontmostVisibleWindowFrame(processIdentifier: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return frontmostVisibleWindowFrame(
            processIdentifier: processIdentifier,
            windows: windows
        )
    }

    static func frontmostVisibleWindowFrame(
        processIdentifier: pid_t,
        windows: [[String: Any]]
    ) -> CGRect? {
        let candidates = windows.compactMap { window -> (layer: Int, frame: CGRect)? in
            guard
                let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                owner.int32Value == processIdentifier,
                let layer = window[kCGWindowLayer as String] as? NSNumber,
                layer.intValue >= 0,
                let alpha = window[kCGWindowAlpha as String] as? NSNumber,
                alpha.doubleValue > 0.01,
                let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(
                    dictionaryRepresentation: boundsDictionary as CFDictionary
                )
            else {
                return nil
            }

            // Ignore tiny helper/transition windows that do not represent an
            // adjustable application window.
            guard bounds.width >= 100 && bounds.height >= 100 else { return nil }
            return (layer: layer.intValue, frame: bounds)
        }

        // Normal application windows remain authoritative. If an application
        // intentionally exposes only an elevated panel (for example Ghostty's
        // non-activating Quick Terminal), use that panel as the visible window.
        return candidates.first(where: { $0.layer == 0 })?.frame
            ?? candidates.first?.frame
    }
}
