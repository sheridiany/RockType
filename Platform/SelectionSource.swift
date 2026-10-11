import AppKit
import ApplicationServices
import RoarkTCore

/// Retains AX identity only for the duration of capture / toolbar display. No window titles.
@MainActor public final class SelectionSource {
    public let source: ContentSnapshot.Source
    private let element: AXUIElement
    private let window: AXUIElement?

    public init?() {
        guard SecureInput.status() == .allowed,
              let app = Accessibility.frontmostApplication,
              app.pid != ProcessInfo.processInfo.processIdentifier,
              let element = Accessibility.focusedElement() else { return nil }
        self.element = element
        window = Self.focusedWindow(pid: app.pid)
        let identifier = window.map { String(CFHash($0)) }
        source = .init(pid: app.pid, bundleID: app.bundleID,
                       applicationName: app.name ?? "来源应用", windowIdentifier: identifier)
    }

    public var isCurrent: Bool {
        guard SecureInput.status() == .allowed,
              Accessibility.frontmostApplication?.pid == source.pid,
              let focused = Accessibility.focusedElement(), CFEqual(element, focused) else { return false }
        let current = Self.focusedWindow(pid: source.pid)
        switch (window, current) {
        case let (original?, current?): return CFEqual(original, current)
        case (nil, nil): return true
        default: return false
        }
    }

    private static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let value = Accessibility.attribute(kAXFocusedWindowAttribute, of: app),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
