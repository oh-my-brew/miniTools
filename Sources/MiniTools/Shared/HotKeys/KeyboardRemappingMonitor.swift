import AppKit
import Carbon
@preconcurrency import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

private let miniToolsRemappingEventCallback: CGEventTapCallBack = {
    _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    let monitorAddress = Int(bitPattern: context)
    return MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: monitorAddress) else {
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged<KeyboardRemappingMonitor>.fromOpaque(pointer).takeUnretainedValue()
            .handle(type: type, event: event)
    }
}

private let miniToolsCapsValueCallback: IOHIDValueCallback = {
    context, _, _, value in
    guard let context else { return }
    let element = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(element) == 0x07,
          IOHIDElementGetUsage(element) == 0x39 else { return }
    let down = IOHIDValueGetIntegerValue(value) != 0
    let monitorAddress = Int(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: monitorAddress) else { return }
        Unmanaged<KeyboardRemappingMonitor>.fromOpaque(pointer).takeUnretainedValue()
            .handleCapsChanged(down: down)
    }
}

/// The system's Caps Lock latch is independent of its physical key-up. Reading and
/// restoring it lets a lone tap remain Caps Lock without turning a chord into Caps Lock.
private final class CapsLockSystemState {
    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOHIDSystem")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType),
                            &connection) == KERN_SUCCESS, connection != 0 else { return nil }
        guard read() != nil else { return nil }
    }

    func read() -> Bool? {
        var value = false
        return IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState),
                                         &value) == KERN_SUCCESS ? value : nil
    }

    @discardableResult
    func set(_ value: Bool) -> Bool {
        IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState),
                                  value) == KERN_SUCCESS
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }
}

@MainActor
final class KeyboardRemappingMonitor {
    var enabled: Set<KeyboardRemappingRule> = []
    var availableCapsKeys: () -> Set<UInt16>
    var perform: (KeyboardRemappingState.Action) -> Void
    private var state = KeyboardRemappingState()
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var hidManager: IOHIDManager?
    private var capsSystem: CapsLockSystemState?
    private var capsOriginalState: Bool?
    private var capsWasReleased = false
    private var capsPhysicalHeld = false
    private(set) var capsAvailable = false
    private static let postedMarker: Int64 = 0x4D54_524D_4150

    init(
        availableCapsKeys: @escaping () -> Set<UInt16>,
        perform: @escaping (KeyboardRemappingState.Action) -> Void
    ) {
        self.availableCapsKeys = availableCapsKeys
        self.perform = perform
    }

    var isRunning: Bool {
        eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    func start() -> Bool {
        if isRunning { return true }
        stop()
        var activeRules = enabled
        if enabled.contains(.capsShortcuts) {
            capsAvailable = startCapsMonitor()
            if !capsAvailable {
                activeRules.remove(.capsShortcuts)
            }
        }
        guard !activeRules.isEmpty else { return false }
        state.enabled = activeRules
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: miniToolsRemappingEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            stop()
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventSource = source
        return true
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let eventSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes)
        }
        eventTap = nil
        eventSource = nil
        if let original = capsOriginalState {
            _ = capsSystem?.set(original)
        }
        if let hidManager {
            IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidManager = nil
        capsSystem = nil
        capsOriginalState = nil
        capsWasReleased = false
        capsPhysicalHeld = false
        capsAvailable = false
        state.reset()
        perform(.cancelShortcuts)
    }

    private func startCapsMonitor() -> Bool {
        guard let capsSystem = CapsLockSystemState() else { return false }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let keyboard: [String: Int] = [
            kIOHIDDeviceUsagePageKey as String: 0x01,
            kIOHIDDeviceUsageKey as String: 0x06
        ]
        IOHIDManagerSetDeviceMatching(manager, keyboard as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(
            manager, miniToolsCapsValueCallback, Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == KERN_SUCCESS else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return false
        }
        self.capsSystem = capsSystem
        hidManager = manager
        return true
    }

    fileprivate func handleCapsChanged(down: Bool) {
        capsPhysicalHeld = down
        capsWasReleased = !down
        if down, capsOriginalState == nil {
            capsOriginalState = capsSystem?.read()
        }
        let outcome = state.capsChanged(down: down)
        for action in outcome.actions { perform(action) }
        if !down, let original = capsOriginalState {
            // Physical Caps Lock may have toggled before the event tap observes it.
            // Preserve a lone tap; a chord restores the previous latch state.
            _ = capsSystem?.set(outcome.used ? original : !original)
            capsOriginalState = nil
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            state.reset()
            perform(.cancelShortcuts)
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.postedMarker {
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .flagsChanged {
            if code == UInt16(kVK_RightCommand) {
                let result = state.rightCommandChanged(
                    down: event.flags.contains(.maskCommand),
                    at: ProcessInfo.processInfo.systemUptime
                )
                for action in result.actions { perform(action) }
            } else if code == UInt16(kVK_CapsLock), capsAvailable {
                // The HID callback handles the physical down/up; the system latch
                // is reconciled on release, without forwarding a Caps modifier.
                if capsWasReleased {
                    capsWasReleased = false
                    return nil
                }
                if capsOriginalState == nil {
                    capsOriginalState = !event.flags.contains(.maskAlphaShift)
                }
                if let original = capsOriginalState {
                    _ = capsSystem?.set(original)
                }
                return nil
            } else {
                state.otherModifierChanged()
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }
        if capsPhysicalHeld { state.availableCapsKeys = availableCapsKeys() }
        let result: KeyboardRemappingState.Result
        if type == .keyDown {
            var modifiers: KeyboardRemappingState.Modifiers = []
            if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
            if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
            if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
            if event.flags.contains(.maskControl) { modifiers.insert(.control) }
            result = state.keyDown(
                code,
                modifiers: modifiers,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                safariFrontmost: code == UInt16(kVK_ANSI_Q)
                    && modifiers == [.command]
                    && enabled.contains(.safariHide)
                    && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari"
            )
        } else {
            result = state.keyUp(code)
        }
        for action in result.actions { perform(action) }
        return result.consume ? nil : Unmanaged.passUnretained(event)
    }

    static func postGrave(_ modifiers: KeyboardRemappingState.Modifiers) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Grave),
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Grave),
                               keyDown: false) else { return }
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: postedMarker)
        up.setIntegerValueField(.eventSourceUserData, value: postedMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
