import AppKit
import QuartzCore

/// Owns only overlay windows and display-local canvases; imported images and preview sessions live elsewhere.
@MainActor final class CaptureOverlayGroup {
    private(set) var panels: [NSPanel] = []
    private(set) var canvases: [CGDirectDisplayID: CaptureCanvas] = [:]
    func add(panel: NSPanel, canvas: CaptureCanvas, displayID: CGDirectDisplayID) {
        panel.contentView = canvas; panels.append(panel); canvases[displayID] = canvas
    }
    /// Prepare all displays before exposing any of them. The nonactivating panels borrow
    /// keyboard focus without replacing the source application's menu bar or switching Space.
    func present(at point: CGPoint, replacing: () -> Void = {}) {
        guard !panels.isEmpty else { return }
        NSDisableScreenUpdates()
        defer { NSEnableScreenUpdates() }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for panel in panels {
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.contentView?.displayIfNeeded()
            panel.displayIfNeeded()
        }
        CATransaction.commit(); CATransaction.flush()
        panels.forEach { $0.orderFrontRegardless() }
        replacing()
        if let panel = panels.first(where: { $0.frame.contains(point) }) {
            panel.makeKey(); panel.makeFirstResponder(panel.contentView)
        }
    }
    func suspend() { panels.forEach { $0.orderOut(nil) } }
    func resume(focusing canvas: CaptureCanvas) {
        panels.forEach { $0.orderFrontRegardless() }
        canvas.window?.makeKey(); canvas.window?.makeFirstResponder(canvas)
    }
    @discardableResult func close() -> Bool {
        let existed = !panels.isEmpty
        panels.forEach { $0.orderOut(nil); $0.contentView = nil }
        panels.removeAll(); canvases.removeAll()
        return existed
    }
    @discardableResult func restore(displayID: CGDirectDisplayID, rect: CGRect) -> Bool {
        guard let target = canvases[displayID], !CaptureGeometry.restored(rect, bounds: target.bounds).isEmpty else { return false }
        for canvas in canvases.values { canvas.restore(.zero) }
        target.restore(rect)
        target.window?.makeKey(); target.window?.makeFirstResponder(target)
        return true
    }
}
