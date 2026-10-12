enum SettingsSection: String, CaseIterable, Identifiable {
    case features, general, input, translation, voice, selection, screenshot, ai, templates, shortcuts, permissions, privacy, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .features: "功能"; case .general: "通用"; case .input: "输入法"; case .translation: "翻译"; case .voice: "语音"
        case .selection: "划词"; case .screenshot: "截图"; case .ai: "AI 连接"; case .templates: "操作模板"
        case .shortcuts: "快捷键"; case .permissions: "权限"; case .privacy: "隐私"; case .about: "关于"
        }
    }
    var symbol: String {
        switch self {
        case .features: "square.grid.2x2"; case .general: "slider.horizontal.3"; case .input: "keyboard"; case .translation: "character.bubble"
        case .voice: "waveform"; case .selection: "cursorarrow.rays"; case .screenshot: "viewfinder"
        case .ai: "sparkles"; case .templates: "square.stack"; case .shortcuts: "command"
        case .permissions: "hand.raised"; case .privacy: "lock.shield"; case .about: "info.circle"
        }
    }
    var detail: String {
        switch self {
        case .features: "按需开启，让 RockType 更合你的习惯。"
        case .general: "让常用工具按你的习惯工作。"
        case .input: "中文输入与候选翻译，保持熟悉的输入节奏。"
        case .translation: "本地优先，显示每次翻译实际使用的引擎。"
        case .voice: "按住 Fn 录音，松开识别并填入，不自动发送。"
        case .selection: "选中文字，在原位置完成阅读与处理。"
        case .screenshot: "主动框选、本地识别，按需交给 AI。"
        case .ai: "管理服务商、模型和连接测试。"
        case .templates: "模板只定义提示词与输出形式。"
        case .shortcuts: "集中管理快捷键，冲突时明确提示。"
        case .permissions: "按需授权，随时可以在系统设置中撤销。"
        case .privacy: "内容留在本次会话，控制权始终在你手中。"
        case .about: "输入、阅读与表达，在一个安静的工具里。"
        }
    }
}
