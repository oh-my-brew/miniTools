import AppKit
import Carbon
import CoreGraphics

protocol ClipboardHistoryEventPosting {
    var canPostEvents: Bool { get }
    func requestAccess() -> Bool
    func postPasteShortcut()
}

struct SystemClipboardHistoryEventPoster: ClipboardHistoryEventPosting {
    var canPostEvents: Bool { CGPreflightPostEventAccess() }

    func requestAccess() -> Bool {
        CGRequestPostEventAccess()
    }

    func postPasteShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

@MainActor
enum ClipboardHistoryPasteService {
    enum PasteError: LocalizedError {
        case unsupportedPlainText
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedPlainText: "此内容不支持纯文本操作"
            case .writeFailed: "无法写入系统剪贴板"
            }
        }
    }

    static func write(
        item: ClipboardHistoryItem,
        payloads: [ClipboardHistoryCapturedRepresentation],
        plainTextOnly: Bool,
        to pasteboard: NSPasteboard = .general
    ) throws {
        guard let objects = ClipboardHistoryCaptureService.itemForWriting(
            item,
            payloads: payloads,
            plainTextOnly: plainTextOnly
        ) else {
            throw PasteError.unsupportedPlainText
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else { throw PasteError.writeFailed }
    }
}
