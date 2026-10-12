import ApplicationServices
import Foundation

enum AccessibilityAuthorizationError: LocalizedError {
    case permissionRequired

    var errorDescription: String? {
        "需要在系统设置中授予 miniTools 辅助功能权限"
    }
}

enum AccessibilityAuthorization {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    static func requirePermission() throws {
        guard isTrusted else {
            _ = requestPermission()
            throw AccessibilityAuthorizationError.permissionRequired
        }
    }
}

enum AccessibilityClient {
    static func systemFocusedProcessIdentifier() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedElement = element(
            from: systemWide,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else {
            return nil
        }

        var processIdentifier: pid_t = 0
        guard
            AXUIElementGetPid(focusedElement, &processIdentifier) == .success,
            processIdentifier > 0
        else {
            return nil
        }
        return processIdentifier
    }

    static func application(for processIdentifier: pid_t, timeout: Float = 1) -> AXUIElement {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, timeout)
        return application
    }

    static func copyValue(
        from element: AXUIElement,
        attribute: CFString
    ) -> (status: AXError, value: CFTypeRef?) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        return (status, value)
    }

    static func element(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        let result = copyValue(from: element, attribute: attribute)
        guard
            result.status == .success,
            let value = result.value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func elements(from element: AXUIElement, attribute: CFString) -> [AXUIElement] {
        let result = copyValue(from: element, attribute: attribute)
        guard result.status == .success else { return [] }
        return result.value as? [AXUIElement] ?? []
    }

    static func string(from element: AXUIElement, attribute: CFString) -> String? {
        let result = copyValue(from: element, attribute: attribute)
        guard result.status == .success else { return nil }
        return result.value as? String
    }

    static func integer(from element: AXUIElement, attribute: CFString) -> Int? {
        let result = copyValue(from: element, attribute: attribute)
        guard result.status == .success else { return nil }
        return (result.value as? NSNumber)?.intValue
    }

    static func boolean(from element: AXUIElement, attribute: CFString) -> Bool? {
        let result = copyValue(from: element, attribute: attribute)
        guard result.status == .success else { return nil }
        return (result.value as? NSNumber)?.boolValue
    }

    static func setValue(
        _ value: CFTypeRef,
        on element: AXUIElement,
        attribute: CFString
    ) -> AXError {
        AXUIElementSetAttributeValue(element, attribute, value)
    }

    static func perform(_ action: CFString, on element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, action)
    }

    static func elementsAreEqual(_ lhs: AXUIElement, _ rhs: AXUIElement?) -> Bool {
        guard let rhs else { return false }
        return CFEqual(lhs, rhs)
    }
}
