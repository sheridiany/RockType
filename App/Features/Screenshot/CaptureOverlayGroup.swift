import AppKit

/// Owns only overlay windows and display-local canvases; imported images and preview sessions live elsewhere.
@MainActor final class CaptureOverlayGroup {
    private(set) var panels: [NSPanel] = []
    private(set) var canvases: [CGDirectDisplayID: CaptureCanvas] = [:]
    func add(panel: NSPanel, canvas: CaptureCanvas, displayID: CGDirectDisplayID) {
        panel.contentView = canvas; panels.append(panel); canvases[displayID] = canvas
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
