import AppKit
import ApplicationServices
import Carbon
import RoarkTCore
import RoarkTPlatform

/// A single-use, memory-only destination captured at Fn-down. No text is read from the field.
@MainActor final class VoicePasteTarget {
    let applicationID: String
    let deadline: TimeInterval
    let validate: () -> Bool
    let post: () throws -> Void
    private var consumed = false
    init(applicationID: String, deadline: TimeInterval, validate: @escaping () -> Bool,
         post: @escaping () throws -> Void) {
        self.applicationID = applicationID; self.deadline = deadline; self.validate = validate; self.post = post
    }
    func consume() -> Bool {
        guard !consumed else { return false }
        consumed = true; return true
    }
}

@MainActor protocol VoicePasting: AnyObject {
    func capture(pid: Int32) -> VoicePasteTarget?
    func paste(_ text: String, target: VoicePasteTarget, allowed: @escaping @MainActor () -> Bool) async throws -> Bool
}

@MainActor final class VoicePasteBridge: VoicePasting {
    private let transaction: ReplacementPasteTransaction
    private let captureFocus: (Int32) -> VoicePasteTarget?
    private let now: () -> TimeInterval
    private let settle: @MainActor () async throws -> Void
    private static let eventTag: Int64 = 0x524B5650
    init(transaction: ReplacementPasteTransaction = .shared,
         captureFocus: @escaping (Int32) -> VoicePasteTarget? = { VoicePasteFocus(pid: $0)?.target() },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         settle: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(350)) }) {
        self.transaction = transaction; self.captureFocus = captureFocus; self.now = now; self.settle = settle
    }
    func capture(pid: Int32) -> VoicePasteTarget? { captureFocus(pid) }
    func paste(_ text: String, target: VoicePasteTarget, allowed: @escaping @MainActor () -> Bool) async throws -> Bool {
        guard target.consume(), now() < target.deadline, text.utf8.count <= 32_768,
              VoiceInsertionPolicy.allowsAutomaticInsertion(text: text, applicationID: target.applicationID) else { return false }
        _ = try await transaction.paste(text, allowed: allowed,
            validate: { self.now() < target.deadline && target.validate() }, post: target.post, settle: settle)
        // CGEvent has no insertion acknowledgement. This means the paste was dispatched, not verified.
        return true
    }
    static func isOwnPaste(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == eventTag
    }
    fileprivate static func post(to pid: Int32) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            throw PlatformReadError.unavailable
        }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
        }
        down.postToPid(pid); up.postToPid(pid)
    }
}

/// Both identity and selection must still match; never activate or rebind a different window.
@MainActor private final class VoicePasteFocus {
    let pid: Int32
    let application: NSRunningApplication
    let applicationID: String
    let app: AXUIElement
    let element: AXUIElement
    let window: AXUIElement
    let selection: CFRange
    init?(pid: Int32) {
        guard SecureInput.status() == .allowed,
              let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == pid,
              let applicationID = front.bundleIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let element = Self.element(kAXFocusedUIElementAttribute, app) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard Self.textInput(element), let window = Self.element(kAXWindowAttribute, element),
              let selection = Self.range(element) else { return nil }
        self.pid = pid; self.application = front; self.applicationID = applicationID; self.app = app
        self.element = element; self.window = window; self.selection = selection
    }
    func target() -> VoicePasteTarget {
        VoicePasteTarget(applicationID: applicationID,
            deadline: ProcessInfo.processInfo.systemUptime + VoiceCommitTicket.dictationLifetime - 10,
            validate: { self.validate() }, post: {
                guard self.validate() else { throw PlatformReadError.sourceChanged }
                try VoicePasteBridge.post(to: self.pid)
            })
    }
    func validate() -> Bool {
        guard !application.isTerminated, SecureInput.status() == .allowed,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == applicationID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = Self.element(kAXFocusedUIElementAttribute, app), CFEqual(focused, element),
              let currentWindow = Self.element(kAXWindowAttribute, focused), CFEqual(currentWindow, window),
              Self.textInput(focused), let range = Self.range(focused) else { return false }
        return range.location == selection.location && range.length == selection.length
    }
    static func attribute(_ key: String, _ element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    static func element(_ key: String, _ parent: AXUIElement) -> AXUIElement? {
        guard let value = attribute(key, parent), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func textInput(_ element: AXUIElement) -> Bool {
        guard let role = attribute(kAXRoleAttribute, element) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              attribute(kAXSubroleAttribute, element) as? String != kAXSecureTextFieldSubrole,
              attribute(kAXEnabledAttribute, element) as? Bool != false else { return false }
        return true
    }
    static func range(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.location != NSNotFound,
              range.length >= 0 else { return nil }
        return range
    }
}
