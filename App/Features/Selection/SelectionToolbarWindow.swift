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

/// Live toolbar uses the same tokens and button treatment as the D0 surface.
struct LiveSelectionToolbar: View {
    let actions: [SelectionToolbarAction]
    let maximumWidth: CGFloat
    let perform: (String) -> Void
    /// ImageRenderer cannot draw AppKit-backed menus; export their label only.
    var renderingSnapshot = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons(compact: false, items: actions)
            buttons(compact: true, items: Array(actions.prefix(compactCount)), overflow: Array(actions.dropFirst(compactCount)))
        }
        .frame(maxWidth: maximumWidth)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(DesignSurface())
        .accessibilityLabel("划词工具栏")
    }

    private var compactCount: Int {
        max(1, Int((maximumWidth - Tokens.Space.xxl * 3) / (Tokens.Size.control + Tokens.Space.sm)) - 1)
    }

    private func buttons(compact: Bool, items: [SelectionToolbarAction], overflow: [SelectionToolbarAction] = []) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(Tokens.palette(scheme).accent)
                .padding(.horizontal, Tokens.Space.sm).accessibilityHidden(true)
            Rectangle().fill(Tokens.palette(scheme).line)
                .frame(width: Tokens.Size.stroke, height: Tokens.Size.compact)
            ForEach(items) { action in
                Button { perform(action.id) } label: {
                    HStack(spacing: Tokens.Space.xs) {
                        Image(systemName: action.symbol)
                        if !compact { Text(action.title).lineLimit(1) }
                    }
                }
                .buttonStyle(DesignButtonStyle(variant: .ghost))
                .disabled(!action.enabled)
                .accessibilityLabel(action.title).help(action.enabled ? action.title : "请前往设置配置 AI 连接")
            }
            if !overflow.isEmpty {
                if renderingSnapshot {
                    Image(systemName: "ellipsis")
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                } else {
                    Menu {
                        ForEach(overflow) { action in
                            Button(action.enabled ? action.title : action.title + " · 请前往设置配置 AI", systemImage: action.symbol) { perform(action.id) }
                                .disabled(!action.enabled)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("更多操作")
                }
            }
        }.padding(Tokens.Space.xs).fixedSize()
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
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        let selection = snapshot.selectionRect.map { ScreenGeometry.topLeft($0, primaryHeight: height) }
        let cursor = ScreenGeometry.mousePosition
        let anchor = selection.map { CGPoint(x: $0.midX, y: $0.midY) } ?? cursor
        guard let screen = ScreenGeometry.screen(containing: anchor) ?? ScreenGeometry.screen(containing: cursor) else { return }
        let maximumWidth = max(Tokens.Size.control, min(Tokens.Size.resultWidth, screen.visibleFrame.width - Tokens.Space.xxl))
        let view = LiveSelectionToolbar(actions: actions, maximumWidth: maximumWidth, perform: perform)
        let host = SelectionHostingView(rootView: view)
        panel.contentView = host
        let size = host.fittingSize
        let placement = Placement.floating(selection: selection, cursor: cursor, size: size, screen: screen.visibleFrame)
        let frame = CGRect(origin: placement.origin, size: size)
        panel.setFrame(ScreenGeometry.topLeft(frame, primaryHeight: height), display: true)
        switch settings.general.appearance {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil); panel.contentView = nil }
}
