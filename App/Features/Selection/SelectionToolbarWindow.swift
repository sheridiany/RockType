import AppKit
import SwiftUI
import RoarkTCore
import RoarkTPlatform

struct SelectionToolbarAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var enabled = true

    static func configured(in settings: AppSettings, aiConfigured: Bool = true) -> [Self] {
        SelectionPolicy.actions(settings: settings).compactMap { id in
            if id == "search" { return Self(id: id, title: "搜索", symbol: "magnifyingglass") }
            if id == "copy" { return Self(id: id, title: "复制", symbol: "doc.on.doc") }
            guard let template = settings.templates.first(where: { $0.id == id }) else { return nil }
            return Self(id: id, title: template.name, symbol: template.icon, enabled: id == "translate" || aiConfigured)
        }
    }
}

/// Nonactivating controls with one shared geometry for icons and labeled actions.
struct LiveSelectionToolbar: View {
    let actions: [SelectionToolbarAction]
    let maximumWidth: CGFloat
    let perform: (String) -> Void
    /// ImageRenderer cannot draw AppKit-backed menus; export their label only.
    var renderingSnapshot = false
    var iconsOnly = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if iconsOnly { compactButtons }
            else {
                ViewThatFits(in: .horizontal) {
                    buttons(compact: false, items: actions)
                    compactButtons
                }
            }
        }
        .frame(maxWidth: maximumWidth)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(DesignSurface())
        .font(Tokens.Typography.font(weight: .medium))
        .foregroundStyle(Tokens.palette(scheme).foreground)
        .accessibilityLabel("划词工具栏")
    }

    private var compactCount: Int {
        let capacity = max(1, Int((maximumWidth - Tokens.Space.lg * 3 + Tokens.Space.xs) / 36))
        return actions.count <= capacity ? actions.count : max(0, capacity - 1)
    }
    private var compactButtons: some View {
        buttons(compact: true, items: Array(actions.prefix(compactCount)), overflow: Array(actions.dropFirst(compactCount)))
    }
    private func buttons(compact: Bool, items: [SelectionToolbarAction], overflow: [SelectionToolbarAction] = []) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, action in
                if index > 0, ["copy", "search"].contains(action.id), !["copy", "search"].contains(items[index - 1].id) {
                    Rectangle().fill(Tokens.palette(scheme).line)
                        .frame(width: Tokens.Size.hairline, height: Tokens.Space.lg)
                        .padding(.horizontal, Tokens.Space.xs)
                }
                Button { perform(action.id) } label: {
                    HStack(spacing: Tokens.Space.sm) {
                        Image(systemName: action.symbol).font(.system(size: 14, weight: .medium))
                            .frame(width: Tokens.Space.lg, height: Tokens.Space.lg)
                        if !compact { Text(action.title).lineLimit(1).fixedSize() }
                    }
                }
                .buttonStyle(SelectionActionStyle())
                .disabled(!action.enabled)
                .accessibilityLabel(action.title).help(action.enabled ? action.title : "请前往设置配置 AI 连接")
            }
            if !overflow.isEmpty {
                if renderingSnapshot {
                    Image(systemName: "ellipsis").frame(width: 32, height: 32)
                } else {
                    Menu {
                        ForEach(overflow) { action in
                            Button(action.enabled ? action.title : action.title + " · 请前往设置配置 AI", systemImage: action.symbol) { perform(action.id) }
                                .disabled(!action.enabled)
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(Tokens.palette(scheme).secondary)
                    .accessibilityLabel("更多操作").help("更多操作")
                }
            }
        }.padding(Tokens.Space.sm).fixedSize()
    }
}

private struct SelectionActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        let p = Tokens.palette(scheme)
        configuration.label.padding(Tokens.Space.sm)
            .foregroundStyle(enabled ? p.foreground : p.tertiary)
            .background(enabled && (hovering || configuration.isPressed) ? p.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).stroke(focused ? p.focus : .clear, lineWidth: 2))
            .contentShape(Rectangle()).onHover { hovering = $0 }
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class SelectionHostingView: NSHostingView<LiveSelectionToolbar> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class SelectionToolbarWindow {
    private let panel = SelectionPanel(contentRect: .zero,
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }
    func contains(_ window: NSWindow?) -> Bool { window === panel }

    init() {
        panel.animationBehavior = .none
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(snapshot: ContentSnapshot, settings: AppSettings, aiConfigured: Bool = true, perform: @escaping (String) -> Void) {
        let actions = SelectionToolbarAction.configured(in: settings, aiConfigured: aiConfigured)
        guard !actions.isEmpty else { hide(); return }
        let selection = snapshot.selectionRect
        let cursor = NSEvent.mouseLocation
        let anchor = selection.map { CGPoint(x: $0.midX, y: $0.midY) } ?? cursor
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
                ?? NSScreen.screens.first(where: { $0.frame.contains(anchor) }) else { hide(); return }
        let maximumWidth = max(Tokens.Size.control, min(Tokens.Size.resultWidth, screen.visibleFrame.width - 16))
        let view = LiveSelectionToolbar(actions: actions, maximumWidth: maximumWidth, perform: perform,
            iconsOnly: settings.selection.toolbarIconsOnly ?? false)
        let host = SelectionHostingView(rootView: view)
        panel.contentView = host
        let size = host.fittingSize
        panel.setFrame(SelectionToolbarLayout.frame(selection: selection, cursor: cursor, size: size,
            screen: screen.visibleFrame), display: true)
        switch settings.general.appearance {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
        // Frequent selection gestures stay immediate; only soften the first opacity change.
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if panel.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() { panel.orderOut(nil); panel.alphaValue = 1; panel.contentView = nil }
}
