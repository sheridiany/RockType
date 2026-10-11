import AppKit
import SwiftUI

@MainActor
final class GalleryWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Tokens.Size.settingsWidth, height: Tokens.Size.settingsHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "RockType · 设计面板"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: GalleryView())
        window.contentMinSize = NSSize(width: Tokens.Size.settingsWidth, height: Tokens.Size.settingsHeight)
        window.setContentSize(window.contentMinSize)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct GalleryView: View {
    @State private var selectedID: String? = GalleryCatalog.entries.first?.id
    @State private var theme: GalleryTheme = .light
    @State private var reduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var selected: GalleryEntry? { GalleryCatalog.entries.first { $0.id == selectedID } }
    var body: some View {
        let p = Tokens.palette(theme.colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Space.lg) {
                Text("设计面板").font(Tokens.Typography.font(weight: .semibold))
                Spacer()
                DesignSegmented(title: "主题", selection: $theme, options: GalleryTheme.allCases.map {
                    DesignOption(title: $0.title, value: $0)
                }).fixedSize()
                DesignToggle(title: "减少动态效果", isOn: $reduceMotion).fixedSize()
            }
            .padding(Tokens.Space.lg)
            Rectangle().fill(p.line).frame(height: Tokens.Size.stroke)
            HStack(spacing: 0) {
                List(selection: $selectedID) {
                    Section("界面 × 状态") {
                        ForEach(GalleryCatalog.entries) { entry in
                            Text(entry.title).tag(entry.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(width: Tokens.Size.gallerySidebar)
                .accessibilityLabel("界面与状态；使用上下方向键选择")
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xxl) {
                        if let selected {
                            Text(selected.title).font(Tokens.Typography.font(Tokens.Typography.input, weight: .medium))
                            GalleryPreview(entry: selected, theme: theme,
                                           reduceMotion: reduceMotion || systemReduceMotion)
                            Text("模拟内容 · 仅验证渲染，示例内操作尚未接入")
                                .font(Tokens.Typography.font(Tokens.Typography.meta))
                                .foregroundStyle(p.secondary)
                        }
                    }
                    .padding(Tokens.Space.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(Tokens.Typography.font()).foregroundStyle(p.foreground)
        .background(p.background).tint(p.accent)
        .environment(\.colorScheme, theme.colorScheme)
        .preferredColorScheme(theme.colorScheme)
    }
}
