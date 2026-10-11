import SwiftUI

/// A view of supplied lifecycle data, never a microphone or a second recorder.
struct VoiceHUDView: View {
    let model: VoicePresentation
    var initiallyExpanded = false
    var onCancel: () -> Void = {}
    var onSettings: () -> Void = {}
    @State private var expanded: Bool?
    private var isExpanded: Bool { expanded ?? initiallyExpanded }
    @Environment(\.colorScheme) private var scheme
    private var hasDetail: Bool { !model.detail.isEmpty }
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack(spacing: Tokens.Space.sm) {
                Image(systemName: model.state.symbol)
                    .foregroundStyle(model.state == .recording || model.state == .failed ? p.danger : model.state == .done ? p.ok : p.secondary)
                    .frame(width: Tokens.Size.compactIcon)
                if model.state == .recording {
                    HStack(alignment: .center, spacing: Tokens.Space.xs) {
                        ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                            Capsule().fill(p.foreground)
                                .frame(width: Tokens.Space.xs, height: max(Tokens.Space.xs, Tokens.U4.waveformHeight * level))
                        }
                    }.frame(width: Tokens.U4.waveformWidth, height: Tokens.U4.waveformHeight)
                        .accessibilityLabel("示例录音波形，松开 Fn 结束")
                    Text(model.elapsed).monospacedDigit().font(Tokens.Typography.font(Tokens.Typography.caption))
                } else {
                    Text(model.state.title).font(Tokens.Typography.font(Tokens.Typography.meta))
                }
                Spacer(minLength: 0)
                if hasDetail {
                    Button(isExpanded ? "收起" : "详情") { expanded = !isExpanded }
                        .buttonStyle(.plain).font(Tokens.Typography.font(Tokens.Typography.caption))
                }
                Button(action: onCancel) { Image(systemName: "xmark").frame(width: Tokens.Size.compact, height: Tokens.Size.compact) }
                    .buttonStyle(.plain).accessibilityLabel(model.state == .recording ? "取消录音" : "关闭语音提示")
            }.frame(minHeight: Tokens.Size.row)
            if hasDetail && (isExpanded) {
                U4Rule()
                Text(model.detail).font(Tokens.Typography.font(Tokens.Typography.meta))
                    .foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true)
                if model.state == .missingModel {
                    Button("前往语音设置", action: onSettings).buttonStyle(DesignButtonStyle(variant: .primary))
                }
            }
        }.padding(.horizontal, Tokens.Space.sm)
            .padding(.bottom, hasDetail && (isExpanded) ? Tokens.Space.md : 0)
            .frame(width: hasDetail ? Tokens.U4.hudDetailWidth : Tokens.U4.hudWidth)
            .modifier(DesignSurface())
            .accessibilityElement(children: .contain).accessibilityLabel("语音输入，" + model.state.title)
    }
}

/// Gallery-only feedback remains local and never claims a real recording took place.
struct VoiceHUDDemo: View {
    let initial: VoicePresentation.State
    let expanded: Bool
    @State private var state: VoicePresentation.State?
    @State private var showSettings = false
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            VoiceHUDView(model: .fixture(state ?? initial), initiallyExpanded: expanded,
                         onCancel: { state = .cancelled }, onSettings: { showSettings = true })
            if showSettings { Notice(text: "预览：请在设置面板的语音分区管理模型。") }
        }
    }
}
