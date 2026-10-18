import Carbon.HIToolbox

/// Global ⌃⌥R / ⌃⌥⇧R via Carbon hotkeys: system-wide, no Accessibility permission needed.
final class HotKeys {
    var onReload: () -> Void = {}
    var onRestart: () -> Void = {}

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func setEnabled(_ enabled: Bool) {
        unregister()
        if enabled { register() }
    }

    fileprivate func fire(_ id: UInt32) {
        id == 1 ? onReload() : onRestart()
    }

    private func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
        let signature = OSType(0x464C_524E)  // "FLRN"
        for (id, modifiers) in [(UInt32(1), controlKey | optionKey), (2, controlKey | optionKey | shiftKey)] {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(modifiers), EventHotKeyID(signature: signature, id: id),
                                GetApplicationEventTarget(), 0, &ref)
            if let ref { refs.append(ref) }
        }
    }

    private func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

nonisolated private func hotKeyCallback(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    let hotKeyID = id.id
    let address = UInt(bitPattern: userData)  // a plain integer can cross into the main-actor closure
    // Carbon delivers hotkey events on the main thread.
    MainActor.assumeIsolated {
        Unmanaged<HotKeys>.fromOpaque(UnsafeRawPointer(bitPattern: address)!).takeUnretainedValue().fire(hotKeyID)
    }
    return noErr
}
