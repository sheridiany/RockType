import AppKit
@preconcurrency import ApplicationServices

@MainActor public enum Accessibility {
    public struct Application: Equatable, Sendable {
        public let pid: pid_t
        public let bundleID: String?
        public let name: String?
    }

    public static func isTrusted(prompt: Bool = false) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
    }

    public static var frontmostApplication: Application? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return Application(pid: app.processIdentifier, bundleID: app.bundleIdentifier, name: app.localizedName)
    }

    static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        guard let value = attribute(kAXFocusedUIElementAttribute, of: system),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }
}
