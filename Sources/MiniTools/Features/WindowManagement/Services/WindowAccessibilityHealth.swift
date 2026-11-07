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
    /// Associate by bounds once, only when unambiguous. Never reselect a
    /// different window from the same process during convergence.
    static func matchingWindowID(processIdentifier: pid_t, accessibilityFrame: CGRect) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let candidates: [(id: CGWindowID, frame: CGRect)] = windows.compactMap { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == processIdentifier,
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0.01,
                  let layer = window[kCGWindowLayer as String] as? NSNumber, layer.intValue >= 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 100, frame.height >= 100
            else { return nil }
            return (number.uint32Value, frame)
        }
        let matches = candidates.filter {
            WindowGeometry.framesAreClose($0.frame, accessibilityFrame, tolerance: 12)
        }
        if matches.count == 1 { return matches[0].id }
        // AX can report the previous request instead of the actual constrained
        // size. A sole visible window is still an unambiguous association.
        return candidates.count == 1 ? candidates[0].id : nil
    }

    static func frame(windowID: CGWindowID, processIdentifier: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let window = windows.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
                    && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier
              }),
              let bounds = window[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

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
