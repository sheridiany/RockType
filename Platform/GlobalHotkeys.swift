import AppKit
import Carbon
import RoarkTCore

@MainActor public final class GlobalHotkeys {
    public enum Failure: Error, Equatable {
        case unsupportedShortcut, conflict, system(OSStatus)
    }
    private struct Registration {
        let reference: EventHotKeyRef
        let handler: @MainActor () -> Void
    }
    private var registrations: [UInt32: Registration] = [:]
    private static var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x524B5448

    public init() {}

    /// Keys are physical ANSI positions, as in the default ⌃1 / ⌃⌥T / ⌃⌥S bindings.
    /// Fn-only shortcuts belong to FnKeyMonitor and cannot be registered with Carbon.
    @discardableResult public func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) throws -> UInt32 {
        let binding = try Self.binding(shortcut)
        var systemKeys: Unmanaged<CFArray>?
        let systemStatus = CopySymbolicHotKeys(&systemKeys)
        guard systemStatus == noErr else { throw Failure.system(systemStatus) }
        if let keys = systemKeys?.takeRetainedValue() as? [[String: Any]], keys.contains(where: { entry in
            (entry[kHISymbolicHotKeyEnabled] as? Bool) == true &&
            (entry[kHISymbolicHotKeyCode] as? NSNumber)?.uint32Value == binding.key &&
            (entry[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value == binding.modifiers
        }) { throw Failure.conflict }
        try installHandler()
        let id = Self.nextID
        guard id < UInt32.max else { throw Failure.system(OSStatus(paramErr)) }
        Self.nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.key, binding.modifiers,
                                        EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &reference)
        if status == OSStatus(eventHotKeyExistsErr) { throw Failure.conflict }
        guard status == noErr, let reference else { throw Failure.system(status) }
        registrations[id] = Registration(reference: reference, handler: handler)
        return id
    }

    public func unregister(_ id: UInt32) throws {
        guard let registration = registrations[id] else { return }
        let status = UnregisterEventHotKey(registration.reference)
        guard status == noErr else { throw Failure.system(status) }
        registrations.removeValue(forKey: id)
    }

    public func stop() {
        for registration in registrations.values { UnregisterEventHotKey(registration.reference) }
        registrations.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private func installHandler() throws {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue()
                guard id.signature == GlobalHotkeys.signature, let registration = owner.registrations[id.id] else {
                    return OSStatus(eventNotHandledErr)
                }
                // Deliver after leaving Carbon's callback; callers must recheck protected input before reading.
                Task { @MainActor [weak owner] in
                    guard let owner, owner.registrations[id.id] != nil else { return }
                    registration.handler()
                }
                return noErr
            }
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard status == noErr else { throw Failure.system(status) }
    }

    static func binding(_ shortcut: Shortcut) throws -> (key: UInt32, modifiers: UInt32) {
        let supported: Shortcut.Modifiers = [.control, .option, .command, .shift]
        guard shortcut.modifiers.subtracting(supported).isEmpty,
              let key = shortcut.key?.lowercased(), let code = keyCodes[key] else { throw Failure.unsupportedShortcut }
        var modifiers: UInt32 = 0
        if shortcut.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return (code, modifiers)
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]

    isolated deinit {
        for registration in registrations.values { UnregisterEventHotKey(registration.reference) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
