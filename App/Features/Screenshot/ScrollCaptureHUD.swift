import AppKit
import SwiftUI

struct ScrollCaptureView: View {
    static let size = CGSize(width: 288, height: 408)
    @Bindable var controller: ScrollCaptureController
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("滚动长截图", systemImage: "rectangle.expand.vertical").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(controller.height) px").font(.system(size: 11, design: .monospaced)).foregroundStyle(p.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(p.canvas)
                if let image = controller.thumbnail {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit).padding(6)
                        .accessibilityLabel("当前已拼接长截图缩略图")
                } else if controller.phase == .preparing { ProgressView().controlSize(.small) }
                else { Image(systemName: "rectangle.dashed").font(.system(size: 28)).foregroundStyle(p.secondary) }
            }.frame(height: 220)
            Text(controller.message).font(.system(size: 12)).foregroundStyle(p.secondary).frame(height: 52, alignment: .topLeading)
            HStack {
                Button("取消 Esc") { controller.cancel() }.buttonStyle(DesignButtonStyle(variant: .ghost))
                Spacer()
                Button("完成并预览") { controller.finish() }.buttonStyle(DesignButtonStyle(variant: .primary)).disabled(!controller.canFinish)
            }
        }.padding(16).frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading).foregroundStyle(p.foreground)
            .background(p.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.line, lineWidth: 1))
    }
}
@MainActor final class ScrollCaptureHUD {
    private var panel: NSPanel?
    private var local: Any?
    private var global: Any?
    func show(_ controller: ScrollCaptureController, near selection: CGRect) {
        close()
        let panel = ScrollHUDPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: ScrollCaptureView(controller: controller))
        panel.setContentSize(ScrollCaptureView.size); panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(selection) })?.visibleFrame ?? selection
        let size = ScrollCaptureView.size
        let x = selection.maxX + 12 + size.width <= screen.maxX ? selection.maxX + 12 : max(screen.minX + 8, selection.minX - size.width - 12)
        panel.setFrameOrigin(CGPoint(x: min(x, screen.maxX - size.width - 8),
            y: min(max(screen.minY + 8, selection.maxY - size.height), screen.maxY - size.height - 8)))
        panel.orderFrontRegardless(); self.panel = panel
        local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak controller] event in
            guard event.keyCode == 53 else { return event }; controller?.cancel(); return nil
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak controller] event in
            if event.keyCode == 53 { controller?.cancel() }
        }
    }
    func close() {
        if let local { NSEvent.removeMonitor(local); self.local = nil }
        if let global { NSEvent.removeMonitor(global); self.global = nil }
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
    }
    isolated deinit { close() }
}
private final class ScrollHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
