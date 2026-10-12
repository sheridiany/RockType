import AppKit
import SwiftUI

/// Presentation measurements only; the editor and window use the same wrapping width.
enum TranslateWindowLayout {
    static let iconSide: CGFloat = 28
    static let minimumHeight: CGFloat = 180
    static func sourceHeight(_ text: String, width: CGFloat, expanded: Bool) -> CGFloat {
        let font = NSFont.systemFont(ofSize: Tokens.Typography.read)
        let storage = NSTextStorage(string: text.isEmpty ? " " : text, attributes: [.font: font])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let line = layout.defaultLineHeight(for: font)
        let used = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        return ceil(min(max(line, used), line * (expanded ? 12 : 4)) + 8)
    }
}

struct TranslateIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        let p = Tokens.palette(scheme)
        configuration.label
            .font(Tokens.Typography.font(Tokens.Size.compactIcon, weight: .medium))
            .frame(width: TranslateWindowLayout.iconSide, height: TranslateWindowLayout.iconSide)
            .foregroundStyle(enabled ? p.secondary : p.tertiary)
            .background(enabled && (hovering || configuration.isPressed) ? p.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).stroke(focused ? p.focus : .clear, lineWidth: 2))
            .contentShape(Rectangle()).onHover { hovering = $0 }
    }
}

struct TranslateHeightPreference: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension View {
    func translationHeight(_ part: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: TranslateHeightPreference.self, value: [part: geometry.size.height])
        })
    }
}
private struct TranslateWidthPreference: PreferenceKey {
    static let defaultValue: CGFloat = 388
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
extension View {
    func translationWidth(_ changed: @escaping (CGFloat) -> Void) -> some View {
        background(GeometryReader { geometry in Color.clear.preference(key: TranslateWidthPreference.self, value: geometry.size.width) })
            .onPreferenceChange(TranslateWidthPreference.self, perform: changed)
    }
}

/// Overlay scrollers keep the language strip centered when long content starts scrolling.
struct TranslateScrollStyle: NSViewRepresentable {
    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); apply() }
        func apply() {
            enclosingScrollView?.scrollerStyle = .overlay
            enclosingScrollView?.autohidesScrollers = true
        }
    }
    func makeNSView(context: Context) -> Anchor {
        let anchor = Anchor(); anchor.setAccessibilityElement(false); return anchor
    }
    func updateNSView(_ view: Anchor, context: Context) { view.apply() }
}
