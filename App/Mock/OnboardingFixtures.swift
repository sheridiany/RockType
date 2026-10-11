import Foundation

enum OnboardingStep: String, CaseIterable, Identifiable {
    case input, language, permissions, voice, ai
    var id: String { rawValue }
    var title: String {
        switch self { case .input: "输入源"; case .language: "语言包"; case .permissions: "权限"; case .voice: "语音模型"; case .ai: "AI 连接" }
    }
    var symbol: String {
        switch self { case .input: "keyboard"; case .language: "character.bubble"; case .permissions: "hand.raised"; case .voice: "waveform"; case .ai: "sparkles" }
    }
    var headline: String {
        switch self {
        case .input: "让 RockType 成为你的输入法"
        case .language: "准备中英离线翻译"
        case .permissions: "只授权你需要的能力"
        case .voice: "按住 Fn，把想法说出来"
        case .ai: "连接你自己的 AI 服务"
        }
    }
    var explanation: String {
        switch self {
        case .input: "添加输入源后，切换到 RockType，再试打一句中文。"
        case .language: "语言包就绪后，候选旁可显示译文；普通输入不必等待。"
        case .permissions: "权限属于主 App；输入法自身不申请隐私权限。"
        case .voice: "本地识别，松开后填入当前输入位置，不自动发送。"
        case .ai: "翻译、总结与润色共用一个连接；只有显式操作才发送内容。"
        }
    }
    var pending: String {
        switch self {
        case .input: "尚未验证输入源。添加到系统后，还需要实际试打。"
        case .language: "中英语言包尚未准备，可先使用静态双语词条。"
        case .permissions: "尚未授权。可以逐项选择，或稍后在设置中授权。"
        case .voice: "模型尚未下载。准备模型不会开启麦克风。"
        case .ai: "尚未配置服务。离线功能仍然可用。"
        }
    }
    var progressing: String {
        switch self {
        case .input: "等待试打验证：请切换到 RockType，在下方输入 nihao。"
        case .language: "正在准备简体中文 ↔ 英文语言包…"
        case .permissions: "等待授权结果。完成后返回这里重新检查。"
        case .voice: "正在下载 0.6B 8bit 模型，完成后将校验文件。"
        case .ai: "正在测试文字、流式、图片与取消能力…"
        }
    }
    var success: String {
        switch self {
        case .input: "试打验证完成 · RockType已就绪。"
        case .language: "简体中文 ↔ 英文语言包已就绪。"
        case .permissions: "所选的辅助功能、屏幕录制、麦克风权限已授权。"
        case .voice: "模型下载与校验完成，下次按住 Fn 即可录音。"
        case .ai: "连接可用，文字、流式、图片与取消测试已完成。"
        }
    }
    var failure: String {
        switch self {
        case .input: "未收到 RockType 的试打确认。请检查当前输入源后再试。"
        case .language: "语言包未能准备完成。请检查网络后重试；输入仍可使用。"
        case .permissions: "麦克风未授权。可前往系统设置修改，或暂时跳过语音。"
        case .voice: "模型校验失败，文件未被加载。请重新下载。"
        case .ai: "连接验证失败：认证未通过。请检查密钥后重试。"
        }
    }
    var action: String {
        switch self {
        case .input: "添加输入源"
        case .language: "准备语言包"
        case .permissions: "按需授权"
        case .voice: "下载模型"
        case .ai: "测试连接"
        }
    }
}

enum OnboardingPhase: String, CaseIterable {
    case pending, progressing, done, skipped, failed
    var title: String {
        switch self { case .pending: "未完成"; case .progressing: "进行中"; case .done: "完成"; case .skipped: "跳过"; case .failed: "失败" }
    }
    var tone: DesignTone {
        switch self { case .pending, .skipped: .neutral; case .progressing: .accent; case .done: .ok; case .failed: .danger }
    }
}

struct OnboardingPresentation {
    let step: OnboardingStep
    let phase: OnboardingPhase
    var message: String {
        switch phase {
        case .pending: step.pending
        case .progressing: step.progressing
        case .done: step.success
        case .skipped: "已跳过\(step.title)。稍后可在设置中继续，不影响已完成的步骤。"
        case .failed: step.failure
        }
    }
}
