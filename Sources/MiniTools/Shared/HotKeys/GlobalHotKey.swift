import Carbon
import Foundation

private let miniToolsHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    let manager = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()

    var receivedID = EventHotKeyID()
    let result = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &receivedID
    )
    guard result == noErr else { return result }
    guard receivedID.id == manager.identifier else { return OSStatus(eventNotHandledErr) }

    let eventKind = GetEventKind(event)
    let receivedAt = ContinuousClock.now
    DispatchQueue.main.async {
        if manager.identifier == 1, eventKind != UInt32(kEventHotKeyReleased) {
            ResponsivenessMetrics.event("PanelHotkeyMainQueue", since: receivedAt)
        }
        if eventKind == UInt32(kEventHotKeyReleased) {
            manager.onReleased?()
        } else {
            manager.onPressed()
        }
    }
    return noErr
}

final class GlobalHotKey: @unchecked Sendable {
    var onPressed: () -> Void
    var onReleased: (() -> Void)?
    fileprivate let identifier: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var registeredShortcut: KeyboardShortcut?
    private var handlerInstallationStatus: OSStatus = noErr

    init(
        identifier: UInt32,
        onPressed: @escaping () -> Void,
        onReleased: (() -> Void)? = nil
    ) {
        self.identifier = identifier
        self.onPressed = onPressed
        self.onReleased = onReleased

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        handlerInstallationStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            miniToolsHotKeyHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    @discardableResult
    func register(_ shortcut: KeyboardShortcut) -> OSStatus {
        guard handlerInstallationStatus == noErr else { return handlerInstallationStatus }
        if shortcut == registeredShortcut, hotKeyRef != nil {
            return noErr
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D_54_4F_4C), id: identifier) // MTOL
        var candidateRef: EventHotKeyRef?
        let result = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &candidateRef
        )
        guard result == noErr, let candidateRef else { return result == noErr ? OSStatus(paramErr) : result }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = candidateRef
        registeredShortcut = shortcut
        return noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registeredShortcut = nil
    }

    deinit {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
