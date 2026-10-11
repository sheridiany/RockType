#if DEBUG
import Foundation


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
                            ("译文上屏（输入法内）", "Tab"), ("输入法内 AI", "⌥Tab"), ("显示设置", "未设置")]
}

#endif
