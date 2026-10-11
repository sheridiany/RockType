import SwiftUI

// Additional surface-specific values derive from the established spacing grid.
// Existing DesignSystem interfaces remain unchanged.
extension Tokens {
    enum U4 {
        static let candidateWidth = Size.resultWidth
        static let modeSide = Space.xl * 2
        static let hudWidth = Space.xxl * 8
        static let hudDetailWidth = Space.xxl * 12
        static let waveformWidth = Space.xxl * 3
        static let waveformHeight = Space.lg
        static let sidebarWidth = Space.xxl * 7
        static let fieldWidth = Space.xxl * 9
        static let toggleWidth = Space.xxl + Space.sm
        static let toggleHeight = Space.xl
        static let toggleKnob = Space.lg
        static let toggleInset = Size.stroke * 2
    }
}

struct U4Rule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(Tokens.palette(scheme).line).frame(height: Tokens.Size.stroke) }
}

struct U4Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md, content: content)
            .padding(Tokens.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.palette(scheme).card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}

struct U4SectionTitle: View {
    let title: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(title).font(Tokens.Typography.font(Tokens.Typography.caption, weight: .semibold))
            .foregroundStyle(Tokens.palette(scheme).secondary)
    }
}

/// Pure SwiftUI progress also renders with ImageRenderer on macOS 14.
struct U4Progress: View {
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
struct U4Toggle: View {
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
                        .frame(width: Tokens.U4.toggleKnob, height: Tokens.U4.toggleKnob)
                        .padding(Tokens.U4.toggleInset)
                }
                .frame(width: Tokens.U4.toggleWidth, height: Tokens.U4.toggleHeight)
                .overlay(Capsule().stroke(p.pillLine, lineWidth: Tokens.Size.stroke))
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(isOn ? "开启" : "关闭")
    }
}

struct U4Choice: View {
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
struct U4EditableField: View {
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
