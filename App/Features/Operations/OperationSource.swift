import AppKit
import ApplicationServices
import RoarkTCore

/// Runtime identity only. Never part of ContentSnapshot or RecentResults.
@MainActor final class OperationSource {
    enum ReturnOutcome { case window, application, unavailable }
    private let application: NSRunningApplication
    private let window: AXUIElement?

    init?(source: ContentSnapshot.Source) {
        guard let app = NSRunningApplication(processIdentifier: source.pid),
              app.bundleIdentifier == source.bundleID, app.isActive else { return nil }
        application = app
        let element = AXUIElementCreateApplication(source.pid)
        AXUIElementSetMessagingTimeout(element, 0.2)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            window = (value as! AXUIElement)
            if let window { AXUIElementSetMessagingTimeout(window, 0.2) }
        } else { window = nil }
    }

    var pid: pid_t { application.processIdentifier }

    func returnToSource() -> ReturnOutcome {
        guard !application.isTerminated,
              let front = NSWorkspace.shared.frontmostApplication,
              front == application || front.processIdentifier == ProcessInfo.processInfo.processIdentifier,
              application.activate(options: []) else { return .unavailable }
        guard let window, AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
            return .application
        }
        return .window
    }
}
