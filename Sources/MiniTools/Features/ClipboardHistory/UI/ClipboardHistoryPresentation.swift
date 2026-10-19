import AppKit
import Foundation

enum ClipboardHistoryHorizontalScrollBehavior {
    static func targetOffset(
        current: CGFloat,
        delta: CGFloat,
        contentWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let maximum = max(0, contentWidth - viewportWidth)
        return min(max(current - delta, 0), maximum)
    }
}

enum ClipboardHistoryInputBehavior {
    static func shouldExpandSearch(
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.contains(.command), !modifiers.contains(.control),
              let characters, !characters.isEmpty else { return false }
        return characters.unicodeScalars.contains(where: {
            !CharacterSet.controlCharacters.contains($0)
        })
    }
}

enum ClipboardHistoryRelativeTimeFormatter {
    static func string(from date: Date, relativeTo now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return "刚刚" }
        if elapsed < 3_600 { return "\(max(1, Int(elapsed / 60))) 分钟前" }
        if elapsed < 86_400 { return "\(max(1, Int(elapsed / 3_600))) 小时前" }
        if elapsed < 7 * 86_400 { return "\(max(1, Int(elapsed / 86_400))) 天前" }

        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 1)月\(components.day ?? 1)日"
    }
}

struct ClipboardHistoryLinkPresentation: Equatable {
    let title: String
    let host: String
    let displayURL: String

    init?(text: String?) {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let rawHost = url.host else { return nil }

        host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let component = url.pathComponents
            .last(where: { $0 != "/" })?
            .removingPercentEncoding?
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        title = component.flatMap { $0.isEmpty ? nil : $0 } ?? host
        displayURL = host + (url.path == "/" ? "" : url.path)
    }
}

enum ClipboardHistoryPreviewLayout {
    static func size(for item: ClipboardHistoryItem) -> CGSize {
        switch item.kind {
        case .image:
            guard let width = item.pixelWidth, let height = item.pixelHeight,
                  width > 0, height > 0 else {
                return CGSize(width: 520, height: 380)
            }
            let aspect = CGFloat(width) / CGFloat(height)
            let maximum = CGSize(width: 620, height: 500)
            var size = CGSize(width: maximum.width, height: maximum.width / aspect)
            if size.height > maximum.height {
                size = CGSize(width: maximum.height * aspect, height: maximum.height)
            }
            return CGSize(width: max(340, size.width), height: max(240, size.height))
        case .richText:
            return textSize(characterCount: item.summary.count, minimumHeight: 320)
        case .text:
            return textSize(characterCount: item.summary.count, minimumHeight: 260)
        case .color:
            return CGSize(width: 380, height: 260)
        case .link:
            return CGSize(width: 500, height: 340)
        case .files:
            return CGSize(width: 560, height: 400)
        }
    }

    private static func textSize(characterCount: Int, minimumHeight: CGFloat) -> CGSize {
        switch characterCount {
        case ..<80:
            return CGSize(width: 420, height: minimumHeight)
        case ..<240:
            return CGSize(width: 480, height: max(minimumHeight, 350))
        default:
            return CGSize(width: 520, height: 440)
        }
    }

    static func frame(
        size: CGSize,
        anchorX: CGFloat,
        panelTop: CGFloat,
        screenFrame: CGRect
    ) -> CGRect {
        let margin: CGFloat = 18
        let gap: CGFloat = 12
        let width = min(size.width, screenFrame.width - margin * 2)
        let height = min(size.height, screenFrame.height - margin * 2)
        let x = min(
            max(anchorX - width / 2, screenFrame.minX + margin),
            screenFrame.maxX - margin - width
        )
        let preferredY = panelTop + gap
        let y = min(preferredY, screenFrame.maxY - margin - height)
        return CGRect(x: x, y: max(screenFrame.minY + margin, y), width: width, height: height)
    }
}
