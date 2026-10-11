import AppKit
import SwiftUI
import RoarkTCore

/// A short, nonactivating acknowledgement; never reads the screen or selection.
@MainActor
final class ComingSoonController {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(_ action: HotkeyCenter.Action) {
        guard [.screenshot, .translateSelection, .summarizeSelection].contains(action) else { return }
        // M2's closed diagnostic vocabulary groups unavailable shortcut actions here.
        Task { try? await DiagnosticLog.shared.record(.init(action: .hotkeyRegistration, status: .unavailable)) }
        show(message: "\(action.title) · 即将推出")
    }

    func show(message: String) {
        dismissal?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView:
            Notice(text: message).padding(Tokens.Space.md).modifier(DesignSurface()))
        let size = panel.contentView!.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 24,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        dismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.panel?.orderOut(nil)
        }
    }

    func stop() { dismissal?.cancel(); dismissal = nil; panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }
}
