import AppKit
import SwiftUI
import RoarkTCore

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MenuBarPanelController {
    private let panel = MenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func toggle<Content: View>(from button: NSStatusBarButton, @ViewBuilder content: () -> Content) {
        if panel.isVisible { close(); return }
        guard let buttonWindow = button.window else { return }
        let hosting = NSHostingView(rootView: content())
        panel.contentView = hosting
        let size = hosting.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = buttonWindow.screen?.visibleFrame ?? anchor
        let x = max(visible.minX, min(anchor.maxX - size.width, visible.maxX - size.width))
        let y = max(visible.minY, min(anchor.minY - size.height, visible.maxY - size.height))
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.type == .keyDown, event.keyCode == 53 { self.close(); return true }
                if event.type != .keyDown, event.window !== self.panel, event.window !== buttonWindow { self.close() }
                return false
            }
            return consumed ? nil : event
        }
        // Mouse-only global monitoring requires no accessibility or input-monitoring grant.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        panel.orderOut(nil)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    @objc private func applicationChanged(_ notification: Notification) { close() }
    func stop() {
        close()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

/// Live counterpart to the U3 presentation, with explicit actions and no fixture content.
struct ShellMenuBarPanel: View {
    let clock: MenuBarClock
    let showClock: Bool
    let aiStatus: String
    var recent: [OperationResult] = []
    var reopen: (OperationResult) -> Void = { _ in }
    var clear: () -> Void = {}
    var screenshot: ScreenshotCoordinator?
    var capture: () -> Void = {}
    let showSettings: () -> Void
    let quit: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Label("RockType", systemImage: "square.stack.3d.up")
                    .font(Tokens.Typography.font(Tokens.Typography.read, weight: .semibold))
                Spacer()
                Button(action: showSettings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("设置").buttonStyle(DesignButtonStyle(variant: .ghost))
            }
            if showClock {
                Text(clock.beijingTime).font(Tokens.Typography.font(Tokens.Typography.display, weight: .semibold))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("北京 · " + clock.beijingDate)
                Text("本地 · " + clock.localTime)
            }.font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
            HStack { Text("最近结果"); Spacer(); Chip(text: aiStatus) }
            if recent.isEmpty {
                Text("本次运行暂无结果。完成文字或图片操作后，结果仅在内存中保留。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        ForEach(recent) { result in
                            Button { reopen(result) } label: {
                                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                    Text(result.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(result.engine).font(Tokens.Typography.font(Tokens.Typography.caption))
                                        .foregroundStyle(p.secondary)
                                }
                            }.buttonStyle(DesignButtonStyle(variant: .ghost))
                        }
                    }
                }.frame(height: min(CGFloat(recent.count) * 66, 264))
            }
            Button("清除当前内容", action: clear).buttonStyle(DesignButtonStyle(variant: .ghost))
            Button(action: capture) {
                HStack { Label("截图", systemImage: "viewfinder"); Spacer(); Text("框选屏幕") }
            }.buttonStyle(DesignButtonStyle(variant: .secondary))
            if let screenshot { ScreenshotImportControls(coordinator: screenshot) }
            U4Rule()
            HStack {
                Spacer()
                Button("设置", action: showSettings).keyboardShortcut(",")
                Kbd("⌘,")
                Button("退出", action: quit)
                Kbd("⌘Q")
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
        }.padding(Tokens.Space.md).frame(width: Tokens.Size.menuWidth).modifier(DesignSurface())
    }
}
