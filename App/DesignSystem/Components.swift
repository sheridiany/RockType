import SwiftUI

// Native Button/Pickers keep keyboard and accessibility behavior on macOS 14.
enum DesignTone { case neutral, accent, ok, warn, danger
    func foreground(_ p: Tokens.Palette) -> Color {
        switch self {
        case .neutral: p.secondary
        case .accent: p.accent
        case .ok: p.ok
        case .warn: p.warn
        case .danger: p.danger
        }
    }
    func background(_ p: Tokens.Palette) -> Color {
        switch self {
        case .neutral: p.bubble
        case .accent: p.accentSoft
        case .ok: p.okSoft
        case .warn: p.warnSoft
        case .danger: p.dangerSoft
        }
    }
}

enum DesignButtonVariant { case primary, secondary, ghost, danger }
struct DesignButtonStyle: ButtonStyle {
    var variant: DesignButtonVariant = .secondary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let p = Tokens.palette(scheme)
        let active = hovering || configuration.isPressed
        let background: Color = switch variant {
        case .primary: active ? p.accentHover : p.accent
        case .secondary: active ? p.pillHover : p.pill
        case .ghost: active ? p.hover : .clear
        case .danger: active ? p.dangerSoft : .clear
        }
        let foreground: Color = switch variant {
        case .primary: p.onAccent
        case .danger: p.danger
        default: p.foreground
        }
        configuration.label
            .font(Tokens.Typography.font(weight: .medium))
            .padding(.horizontal, Tokens.Space.sm)
            .frame(minHeight: Tokens.Size.control)
            .foregroundStyle(enabled ? foreground : p.tertiary)
            .background(enabled ? background : p.bubble,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control)
                .stroke(variant == .secondary ? p.pillLine : .clear, lineWidth: Tokens.Size.stroke))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : Tokens.Motion.hover, value: active)
    }
}

struct Kbd: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: Tokens.Typography.caption, design: .monospaced))
            .foregroundStyle(Tokens.palette(scheme).tertiary)
    }
}

struct Chip: View {
    let text: String
    var tone: DesignTone = .neutral
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        Text(text).font(Tokens.Typography.font(Tokens.Typography.caption, weight: .medium))
            .padding(.horizontal, Tokens.Space.sm).padding(.vertical, Tokens.Space.xs)
            .foregroundStyle(tone.foreground(p))
            .background(tone.background(p), in: Capsule())
    }
}

struct ActionRow: View {
    let title: String
    let symbol: String
    var shortcut: String? = nil
    var selected = false
    var disabledReason: String? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.sm) {
                Image(systemName: symbol).frame(width: Tokens.Size.icon)
                Text(title)
                Spacer()
                if let disabledReason { Text(disabledReason).font(Tokens.Typography.font(Tokens.Typography.caption)) }
                if let shortcut { Kbd(shortcut) }
            }
            .frame(minHeight: Tokens.Size.row)
            .padding(.horizontal, Tokens.Space.xs)
            .background(selected ? Tokens.palette(scheme).selected : .clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
        .buttonStyle(DesignButtonStyle(variant: .ghost))
        .disabled(disabledReason != nil)
        .accessibilityValue(disabledReason ?? (selected ? "已选择" : ""))
    }
}

enum ResultStatus: String, CaseIterable {
    case connecting = "连接中", streaming = "流式中", done = "已完成"
    case incomplete = "不完整", cancelled = "已取消", error = "失败"
    var symbol: String {
        switch self {
        case .connecting: "ellipsis.circle"
        case .streaming: "text.line.first.and.arrowtriangle.forward"
        case .done: "checkmark.circle"
        case .incomplete: "exclamationmark.circle"
        case .cancelled: "stop.circle"
        case .error: "xmark.circle"
        }
    }
    var tone: DesignTone {
        switch self {
        case .connecting, .streaming: .accent
        case .done: .ok
        case .incomplete: .warn
        case .cancelled: .neutral
        case .error: .danger
        }
    }
}
struct StatusLine: View {
    let status: ResultStatus
    let detail: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            Image(systemName: status.symbol).foregroundStyle(status.tone.foreground(Tokens.palette(scheme)))
            Text(status.rawValue)
            Text("· " + detail)
        }
        .font(Tokens.Typography.font(Tokens.Typography.meta))
        .foregroundStyle(Tokens.palette(scheme).secondary)
        .accessibilityElement(children: .combine)
    }
}

struct DesignTextField: View {
    let title: String
    @Binding var text: String
    var error: String? = nil
    @FocusState private var focused: Bool
    var body: some View {
        FieldContainer(error: error, focused: focused) {
            TextField(title, text: $text).textFieldStyle(.plain).focused($focused)
                .frame(minHeight: Tokens.Size.field)
                .accessibilityLabel(title)
        }
    }
}
struct DesignTextArea: View {
    let title: String
    @Binding var text: String
    var error: String? = nil
    @FocusState private var focused: Bool
    var body: some View {
        FieldContainer(error: error, focused: focused) {
            TextEditor(text: $text).scrollContentBackground(.hidden).focused($focused)
                .frame(minHeight: Tokens.Size.row * 3)
                .accessibilityLabel(title)
        }
    }
}
private struct FieldContainer<Content: View>: View {
    let error: String?
    let focused: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            content().font(Tokens.Typography.font())
                .foregroundStyle(enabled ? p.foreground : p.tertiary)
                .padding(.horizontal, Tokens.Space.sm).padding(.vertical, Tokens.Space.xs)
                .background(enabled ? p.pill : p.bubble, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card)
                    .stroke(error != nil ? p.danger : p.pillLine, lineWidth: Tokens.Size.stroke))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card)
                    .stroke(focused ? p.focus : .clear, lineWidth: Tokens.Size.focusRing))
            if let error { Text(error).font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.danger) }
        }
    }
}

struct Notice: View {
    let text: String
    var tone: DesignTone = .neutral
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        HStack(spacing: Tokens.Space.sm) {
            Image(systemName: tone == .danger ? "exclamationmark.circle" : "info.circle")
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(DesignButtonStyle(variant: .ghost))
            }
        }
        .font(Tokens.Typography.font()).foregroundStyle(tone.foreground(p))
        .padding(Tokens.Space.md)
        .background(tone.background(p), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: Tokens.Space.md) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(title)
                if let detail { Text(detail).font(Tokens.Typography.font(Tokens.Typography.caption))
                    .foregroundStyle(Tokens.palette(scheme).secondary) }
            }
            Spacer()
            content()
        }
        .font(Tokens.Typography.font())
        .frame(minHeight: Tokens.Size.row).padding(.horizontal, Tokens.Space.md)
        .padding(.vertical, Tokens.Space.sm)
        .background(Tokens.palette(scheme).card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}

struct DesignToggle: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.switch)
            .font(Tokens.Typography.font()).tint(Tokens.palette(scheme).accent)
    }
}
struct DesignOption<Value: Hashable>: Identifiable {
    let title: String
    let value: Value
    var id: Value { value }
}
struct DesignSegmented<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [DesignOption<Value>]
    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options) { Text($0.title).tag($0.value) }
        }.pickerStyle(.segmented).font(Tokens.Typography.font()).accessibilityLabel(title)
    }
}
struct DesignSelect<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [DesignOption<Value>]
    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options) { Text($0.title).tag($0.value) }
        }.pickerStyle(.menu).font(Tokens.Typography.font()).accessibilityLabel(title)
    }
}
