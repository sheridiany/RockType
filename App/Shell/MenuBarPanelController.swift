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
        let root = content()
        let hosting = NSHostingView(rootView: root)
        panel.contentView = hosting
        var size = hosting.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = buttonWindow.screen?.visibleFrame ?? anchor
        if size.height > visible.height - Tokens.Space.lg {
            size.height = max(1, visible.height - Tokens.Space.lg)
            panel.contentView = NSHostingView(rootView: ScrollView { root }
                .frame(width: size.width, height: size.height))
        }
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
    var pinHistoryCount = 0
    var restorePin: () -> Void = {}
    var hasPassthroughPins = false
    var exitPinPassthrough: () -> Void = {}
    var prepareImageAction: () -> Void = {}
    let showSettings: () -> Void
    let quit: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                SettingsBrand()
                Spacer()
                Button(action: showSettings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("设置").buttonStyle(DesignButtonStyle(variant: .ghost))
            }
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                if showClock {
                    Text(clock.beijingTime).font(Tokens.Typography.font(Tokens.Typography.display, weight: .semibold))
                        .monospacedDigit().accessibilityLabel("北京时间 " + clock.beijingTime)
                }
                Text("北京 · " + clock.beijingDate)
                Text("本地 · " + clock.localTime)
                    .foregroundStyle(p.textTertiary)
            }.font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                .padding(Tokens.Space.md).frame(maxWidth: .infinity, alignment: .leading)
                .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            HStack {
                U4SectionTitle(title: "最近结果")
                Spacer()
                Text("\(recent.count) / 10").monospacedDigit()
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                    .accessibilityLabel("本次运行保留 \(recent.count) 条结果")
            }
            if recent.isEmpty {
                MenuRecentEmptyState()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        ForEach(recent) { result in
                            Button { reopen(result) } label: {
                                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                    Text(result.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(result.engine).lineLimit(1).font(Tokens.Typography.font(Tokens.Typography.caption))
                                        .foregroundStyle(p.secondary)
                                }
                            }.buttonStyle(DesignButtonStyle(variant: .ghost))
                        }
                    }
                }.frame(height: min(CGFloat(recent.count) * Tokens.Size.recentResultRow, Tokens.Size.recentResultsMaxHeight))
                    .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            }
            Button("清除当前内容", action: clear).buttonStyle(DesignButtonStyle(variant: .ghost))
            Button(action: capture) {
                HStack { Label("截图", systemImage: "viewfinder"); Spacer(); Text("框选屏幕").font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary) }
            }.buttonStyle(DesignButtonStyle(variant: .secondary))
            if let screenshot { ScreenshotImportControls(coordinator: screenshot, prepare: prepareImageAction) }
            Button("找回最近关闭的贴图（\(pinHistoryCount)）", action: restorePin)
                .buttonStyle(DesignButtonStyle(variant: .ghost)).disabled(pinHistoryCount == 0)
            if hasPassthroughPins {
                Button("退出贴图鼠标穿透", action: exitPinPassthrough)
                    .buttonStyle(DesignButtonStyle(variant: .secondary))
            }
            U4Rule()
            Label(aiStatus, systemImage: "sparkles")
                .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("设置", action: showSettings).keyboardShortcut(",")
                Kbd("⌘,")
                Button("退出", action: quit)
                Kbd("⌘Q")
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
        }.padding(Tokens.Space.md).frame(width: Tokens.Size.menuWidth).modifier(DesignSurface())
            .accessibilityElement(children: .contain).accessibilityLabel("RockType 菜单栏面板")
    }
}
