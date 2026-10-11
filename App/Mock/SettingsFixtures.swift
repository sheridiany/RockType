import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, input, translation, voice, selection, screenshot, ai, templates, shortcuts, permissions, privacy, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "通用"; case .input: "输入法"; case .translation: "翻译"; case .voice: "语音"
        case .selection: "划词"; case .screenshot: "截图"; case .ai: "AI 连接"; case .templates: "操作模板"
        case .shortcuts: "快捷键"; case .permissions: "权限"; case .privacy: "隐私"; case .about: "关于"
        }
    }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"; case .input: "keyboard"; case .translation: "character.bubble"
        case .voice: "waveform"; case .selection: "cursorarrow.rays"; case .screenshot: "viewfinder"
        case .ai: "sparkles"; case .templates: "square.stack"; case .shortcuts: "command"
        case .permissions: "hand.raised"; case .privacy: "lock.shield"; case .about: "info.circle"
        }
    }
    var detail: String {
        switch self {
        case .general: "让常用工具按你的习惯工作。"
        case .input: "中文输入与候选翻译，保持熟悉的输入节奏。"
        case .translation: "本地优先，显示每次翻译实际使用的引擎。"
        case .voice: "按住 Fn 录音，松开识别并填入，不自动发送。"
        case .selection: "选中文字，在原位置完成阅读与处理。"
        case .screenshot: "主动框选、本地识别，按需交给 AI。"
        case .ai: "一个服务商连接，供翻译、总结与润色使用。"
        case .templates: "模板只定义提示词与输出形式。"
        case .shortcuts: "集中管理快捷键，冲突时明确提示。"
        case .permissions: "按需授权，随时可以在系统设置中撤销。"
        case .privacy: "内容留在本次会话，控制权始终在你手中。"
        case .about: "输入、阅读与表达，在一个安静的工具里。"
        }
    }
}

struct SettingsPresentation {
    enum Scenario: String {
        case normal = "default", unconfigured, testing, mixed, conflict, denied, downloading, edited, actions, installed
    }
    let section: SettingsSection
    var scenario: Scenario = .normal
    var values: [String: String] {
        ["language": "跟随系统", "search": "Google", "scheme": "全拼", "target": "自动（中 ⇄ 英）",
         "engine": "Apple 离线优先", "model": "0.6B · 8bit", "trigger": "划词即出", "opacity": "100%",
         "filter": "黑名单", "apps": "Finder", "name": scenario == .unconfigured ? "" : "示例服务",
         "url": scenario == .unconfigured ? "" : "https://api.example.com/v1",
         "ai-model": scenario == .unconfigured ? "" : "example-text", "vision-model": "example-vision",
         "template": "翻译", "template-name": "翻译", "template-icon": "文", "input-type": "文字",
         "output": "原文对照", "prompt": scenario == .edited ? "请翻译为目标语言，保留段落与术语，并给出一句简短说明。" : "请将以下内容翻译为 {{target}}，保留段落、列表和代码块。",
         "translation-model": "默认模型", "assistant-model": "默认模型", "theme": "跟随系统", "format": "PNG"]
    }
}

enum SettingsFixtures {
    static let all: [SettingsPresentation] = SettingsSection.allCases.map { SettingsPresentation(section: $0) } + [
        .init(section: .ai, scenario: .unconfigured), .init(section: .ai, scenario: .testing),
        .init(section: .ai, scenario: .mixed), .init(section: .shortcuts, scenario: .conflict),
        .init(section: .permissions, scenario: .denied), .init(section: .voice, scenario: .downloading),
        .init(section: .templates, scenario: .edited), .init(section: .selection, scenario: .actions),
        .init(section: .voice, scenario: .installed)
    ]
    static let shortcuts = [("翻译选区", "⌃⌥T"), ("总结选区", "⌃⌥S"), ("截图", "⌃1"),
                            ("语音：按住说话", "Fn"), ("中英切换（输入法内）", "Shift"),
                            ("译文上屏（输入法内）", "Tab"), ("输入法内 AI", "待定义"), ("显示设置", "未设置")]
}
