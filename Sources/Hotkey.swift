// Hotkey.swift -- Carbon global hotkeys (no Accessibility permission). Same plumbing as spike/main.swift.
import AppKit
import Carbon

enum HotkeyEvent { case press, release, escape }

/// Set by the app; the C callback below cannot capture context.
var gHotkeyHandler: ((HotkeyEvent) -> Void)? = nil

func imageRingHotkeyCallback(_ next: EventHandlerCallRef?, _ ev: EventRef?, _ ud: UnsafeMutableRawPointer?) -> OSStatus {
    guard let ev = ev else { return noErr }
    var hk = EventHotKeyID()
    GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    let kind = GetEventKind(ev)
    switch (kind, hk.id) {
    case (UInt32(kEventHotKeyPressed), 1): gHotkeyHandler?(.press)
    case (UInt32(kEventHotKeyReleased), 1): gHotkeyHandler?(.release)
    case (UInt32(kEventHotKeyPressed), 2): gHotkeyHandler?(.escape)
    default: break
    }
    return noErr
}

final class Hotkey {
    static let shared = Hotkey()
    private static let signature = OSType(0x494d4752)   // 'IMGR'
    private var installed = false
    private var mainRef: EventHotKeyRef?
    private var escRef: EventHotKeyRef?

    /// Installs the Carbon event handler once. Returns the OSStatus of the install.
    @discardableResult
    func installHandler() -> OSStatus {
        if installed { return noErr }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let st = InstallEventHandler(GetApplicationEventTarget(), imageRingHotkeyCallback, 2, &specs, nil, nil)
        installed = (st == noErr)
        return st
    }

    /// Control+Option+Space.
    @discardableResult
    func registerMain() -> OSStatus {
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: Hotkey.signature, id: 1),
                            GetApplicationEventTarget(), 0, &mainRef)
    }

    func unregisterMain() {
        if let r = mainRef { UnregisterEventHotKey(r); mainRef = nil }
    }

    /// Esc, registered only while the ring is open.
    @discardableResult
    func registerEscape() -> OSStatus {
        if escRef != nil { return noErr }
        return RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: Hotkey.signature, id: 2),
                                   GetApplicationEventTarget(), 0, &escRef)
    }

    func unregisterEscape() {
        if let r = escRef { UnregisterEventHotKey(r); escRef = nil }
    }
}
