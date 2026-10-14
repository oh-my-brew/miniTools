import AppKit
import SwiftUI

@MainActor
struct ASCIIQueryTextField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let focusRequestID: Int
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 16)
        textField.placeholderString = placeholder
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.stringValue = text
        context.coordinator.focusWhenReady(textField, requestID: focusRequestID)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        if textField.stringValue != text {
            let cursor = textField.currentEditor()?.selectedRange.location ?? text.utf16.count
            textField.stringValue = text
            textField.currentEditor()?.selectedRange = NSRange(
                location: min(cursor, text.utf16.count),
                length: 0
            )
        }
        context.coordinator.focusWhenReady(textField, requestID: focusRequestID)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ASCIIQueryTextField
        private var completedFocusRequestID: Int?

        init(parent: ASCIIQueryTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            let rawValue = textField.stringValue
            let sanitized = EncodingConversionPanelViewModel.sanitizeSearchQuery(rawValue)

            if sanitized != rawValue {
                let cursor = textField.currentEditor()?.selectedRange.location ?? sanitized.utf16.count
                textField.stringValue = sanitized
                textField.currentEditor()?.selectedRange = NSRange(
                    location: min(cursor, sanitized.utf16.count),
                    length: 0
                )
            }
            if parent.text != sanitized {
                parent.onChange(sanitized)
            }
        }

        func focusWhenReady(_ textField: NSTextField, requestID: Int) {
            guard completedFocusRequestID != requestID else { return }
            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self, let textField, let window = textField.window else { return }
                if window.makeFirstResponder(textField) {
                    completedFocusRequestID = requestID
                }
            }
        }
    }
}
