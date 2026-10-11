import AppKit
import SwiftUI

/// Only the settings window's input modality affects its sidebar focus decoration.
struct SettingsSidebarInteraction: NSViewRepresentable {
    let keyboardNavigation: (Bool) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.keyboardNavigation = keyboardNavigation }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var keyboardNavigation: ((Bool) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, event.window === window else { return }
                    if event.type != .keyDown { self.keyboardNavigation?(false) }
                    else if event.keyCode == 48 { self.keyboardNavigation?(true) }
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        isolated deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
