import SwiftUI

// Additional surface-specific values derive from the established spacing grid.
// Existing DesignSystem interfaces remain unchanged.

struct DesignRule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(Tokens.palette(scheme).line).frame(height: Tokens.Size.stroke) }
}

struct DesignCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md, content: content)
            .padding(Tokens.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.palette(scheme).card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}

struct DesignSectionTitle: View {
    let title: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(title).font(Tokens.Typography.font(Tokens.Typography.caption, weight: .semibold))
            .foregroundStyle(Tokens.palette(scheme).secondary)
    }
}

/// Pure SwiftUI progress also renders with ImageRenderer on macOS 14.
struct DesignProgress: View {
    let value: Double
    let label: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Text(label).font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
            GeometryReader { geometry in
                Capsule().fill(p.bubble)
                Capsule().fill(p.accent).frame(width: geometry.size.width * min(1, max(0, value)))
            }.frame(height: Tokens.Space.xs)
        }.accessibilityElement(children: .ignore).accessibilityLabel(label)
            .accessibilityValue("\(Int(min(1, max(0, value)) * 100))%")
    }
}

/// Native actions, custom drawing: unlike AppKit-backed switches this is fully exportable.
struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        let p = Tokens.palette(scheme)
        Button { isOn.toggle() } label: {
            Capsule().fill(isOn && enabled ? p.accent : p.bubble)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(enabled ? (isOn ? p.onAccent : (scheme == .dark ? p.secondary : p.card)) : p.tertiary)
                        .frame(width: Tokens.Size.toggleKnob, height: Tokens.Size.toggleKnob)
                        .padding(Tokens.Size.toggleInset)
                }
                .frame(width: Tokens.Size.toggleWidth, height: Tokens.Size.toggleHeight)
                .overlay(Capsule().stroke(p.pillLine, lineWidth: Tokens.Size.stroke))
        }.buttonStyle(DesignToggleButtonStyle())
            .accessibilityRepresentation {
                Toggle(title, isOn: $isOn).toggleStyle(.switch).disabled(!enabled)
            }
    }
}

struct DesignChoice: View {
    let title: String
    @Binding var value: String
    let options: [String]
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: Tokens.Space.sm) {
                Text(value)
                Image(systemName: "chevron.up.chevron.down").font(Tokens.Typography.font(Tokens.Typography.caption))
            }
        }.buttonStyle(DesignButtonStyle()).accessibilityLabel(title).accessibilityValue(value)
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    ForEach(options, id: \.self) { option in
                        Button(option) { value = option; showing = false }
                            .buttonStyle(DesignButtonStyle(variant: value == option ? .primary : .ghost))
                    }
                }.padding(Tokens.Space.sm)
            }
    }
}

/// Inline value stays drawable in exports; editing is an explicit native sheet.
struct DesignEditableField: View {
    let title: String
    @Binding var value: String
    var multiline = false
    @State private var editing = false
    @State private var draft = ""
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        Button { draft = value; editing = true } label: {
            Text(value.isEmpty ? title : value)
                .foregroundStyle(value.isEmpty ? p.tertiary : p.foreground)
                .font(Tokens.Typography.font(Tokens.Typography.meta))
                .frame(maxWidth: .infinity, minHeight: Tokens.Size.field, alignment: .leading)
                .padding(.horizontal, Tokens.Space.sm)
                .padding(.vertical, multiline ? Tokens.Space.sm : 0)
                .background(p.pill, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).stroke(p.pillLine, lineWidth: Tokens.Size.stroke))
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value).help("编辑" + title)
            .sheet(isPresented: $editing) {
                VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                    Text(title).font(Tokens.Typography.font(Tokens.Typography.input, weight: .medium))
                    if multiline { DesignTextArea(title: title, text: $draft) }
                    else { DesignTextField(title: title, text: $draft) }
                    HStack {
                        Spacer()
                        Button("取消") { editing = false }.keyboardShortcut(.cancelAction)
                        Button("完成") { value = draft; editing = false }.keyboardShortcut(.defaultAction)
                    }
                }.padding(Tokens.Space.xxl).frame(width: Tokens.Size.resultWidth)
            }
    }
}

/// The compact switch keeps its geometry while exposing a visible keyboard focus ring.
private struct DesignToggleButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .overlay(Capsule().stroke(focused ? Tokens.palette(scheme).focus : .clear,
                                      lineWidth: Tokens.Size.focusRing).allowsHitTesting(false))
    }
}
