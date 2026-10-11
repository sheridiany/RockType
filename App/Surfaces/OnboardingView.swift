import SwiftUI

struct OnboardingView: View {
    let model: OnboardingPresentation
    let onAction: () -> Void
    let onSkip: () -> Void
    let onNext: () -> Void
    let onStep: (OnboardingStep) -> Void
    @State private var trial = ""
    @State private var service = "示例服务"
    @State private var endpoint = "https://api.example.com/v1"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            HStack {
                Text("欢迎使用 RockType").font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                Spacer()
                Text("\((OnboardingStep.allCases.firstIndex(of: model.step) ?? 0) + 1) / \(OnboardingStep.allCases.count)")
                    .monospacedDigit().foregroundStyle(p.secondary)
            }
            HStack(spacing: Tokens.Space.sm) {
                ForEach(OnboardingStep.allCases) { step in
                    Button { onStep(step) } label: {
                        HStack(spacing: Tokens.Space.sm) {
                            Image(systemName: step.symbol)
                            Text(step.title)
                        }.frame(maxWidth: .infinity, minHeight: Tokens.Size.row)
                            .foregroundStyle(step == model.step ? p.accent : p.secondary)
                            .background(step == model.step ? p.accentSoft : p.card,
                                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                    }.buttonStyle(.plain).accessibilityAddTraits(step == model.step ? .isSelected : [])
                }
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                    Text(model.step.headline).font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                    Text(model.step.explanation).foregroundStyle(p.secondary)
                }
                Spacer()
                Chip(text: model.phase.title, tone: model.phase.tone)
            }
            U4Card { stepContent }
            Notice(text: model.message, tone: model.phase.tone)
            Spacer(minLength: 0)
            U4Rule()
            HStack {
                Button("跳过此步", action: onSkip).buttonStyle(DesignButtonStyle(variant: .ghost))
                    .disabled(model.phase == .skipped)
                Text("以后可在设置中继续").font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                Spacer()
                if model.phase == .done || model.phase == .skipped {
                    Button(model.step == .ai ? "开始使用" : "继续", action: onNext)
                        .buttonStyle(DesignButtonStyle(variant: .primary))
                } else {
                    Button(actionTitle, action: onAction).buttonStyle(DesignButtonStyle(variant: .primary))
                }
            }
        }.padding(Tokens.Space.xxl)
            .frame(width: Tokens.Size.settingsWidth, height: Tokens.Size.settingsHeight)
            .font(Tokens.Typography.font()).foregroundStyle(p.foreground)
            .background(p.background, in: RoundedRectangle(cornerRadius: Tokens.Radius.window))
    }

    private var actionTitle: String {
        if model.phase == .failed { return "重试" }
        if model.phase == .progressing { return model.step == .input ? "验证试打" : "重新检查" }
        return model.step.action
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .input:
            Text("系统设置 → 键盘 → 文本输入 → 编辑 → ＋ → 简体中文")
                .font(Tokens.Typography.font(Tokens.Typography.meta))
            HStack { Text("RockType Pinyin / RockType Shuangpin"); Spacer(); Kbd("Shift 中英切换") }
            U4EditableField(title: "在这里试打 nihao，按空格选择中文", value: $trial)
            Text("候选每页 5 项，译文独立显示，Tab 上屏。")
                .font(Tokens.Typography.font(Tokens.Typography.caption))
        case .language:
            Label("简体中文 ↔ English", systemImage: "arrow.left.arrow.right")
            Text("Apple 动态翻译需要 macOS 26；较早系统可用静态词条，或显式开启 AI。")
                .font(Tokens.Typography.font(Tokens.Typography.meta))
            HStack {
                Chip(text: model.phase == .done ? "语言包已就绪" : "静态词条可用", tone: .ok)
                Spacer()
                Text("仅在设备上翻译").font(Tokens.Typography.font(Tokens.Typography.meta))
            }
        case .permissions:
            ForEach([("辅助功能", "读取选区与返回来源"), ("屏幕录制", "仅在主动截图时使用"), ("麦克风", "仅在按住 Fn 时录音")], id: \.0) { title, detail in
                HStack {
                    Text(title)
                    Text(detail).font(Tokens.Typography.font(Tokens.Typography.meta))
                    Spacer()
                    Chip(text: model.phase == .done ? "已授权" : "未授权", tone: model.phase == .done ? .ok : .warn)
                }
            }
        case .voice:
            HStack {
                VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                    Text("Qwen3-ASR · 0.6B · 8bit").font(Tokens.Typography.font(weight: .medium))
                    Text("默认模型 · 另有 1.7B 8bit 可在设置中切换")
                        .font(Tokens.Typography.font(Tokens.Typography.meta))
                }
                Spacer()
                Image(systemName: "waveform").font(Tokens.Typography.font(Tokens.Typography.display))
            }
            if model.phase == .progressing {
                U4Progress(value: 0.42, label: "下载中 · 42% · 336 MB / 800 MB（示例）")
            } else {
                Text(model.phase == .done ? "文件校验通过 · 准备模型不会开始录音" : "需下载约 800 MB（示例大小） · 可随时取消")
                    .font(Tokens.Typography.font(Tokens.Typography.meta))
            }
        case .ai:
            HStack { Text("名称"); U4EditableField(title: "服务名称", value: $service) }
            HStack { Text("Base URL"); U4EditableField(title: "Base URL", value: $endpoint) }
            HStack {
                Text("密钥仅存钥匙串").font(Tokens.Typography.font(Tokens.Typography.meta))
                Spacer()
                Chip(text: model.phase == .pending || model.phase == .skipped ? "未设置" : "已设置", tone: .neutral)
            }
        }
    }
}

/// Only these preview transitions are simulated; the surface receives presentation data.
struct OnboardingDemo: View {
    @State private var step: OnboardingStep
    @State private var phases: [OnboardingStep: OnboardingPhase]
    @State private var finished = false
    init(step: OnboardingStep, phase: OnboardingPhase) {
        _step = State(initialValue: step)
        _phases = State(initialValue: [step: phase])
    }
    var body: some View {
        OnboardingView(model: OnboardingPresentation(step: step, phase: phases[step] ?? .pending),
            onAction: { phases[step] = phases[step] == .progressing ? .done : .progressing },
            onSkip: { phases[step] = .skipped }, onNext: advance, onStep: { step = $0 })
            .alert("引导预览已完成", isPresented: $finished) { Button("返回预览", role: .cancel) {} }
                message: { Text("未修改输入源、权限、语言包或 AI 配置。") }
    }
    private func advance() {
        guard let index = OnboardingStep.allCases.firstIndex(of: step), index + 1 < OnboardingStep.allCases.count else {
            finished = true
            return
        }
        step = OnboardingStep.allCases[index + 1]
    }
}
