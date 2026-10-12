#if DEBUG
import SwiftUI

/// All edits below are in-memory presentation state, not application preferences.
struct SettingsView: View {
    @State private var section: SettingsSection
    @State private var scenario: SettingsPresentation.Scenario
    @State private var values: [String: String]
    @State private var toggles: [String: Bool] = ["fuzzy": true, "correction": true, "candidate": true, "selection": true,
        "fallback": true, "follow": true, "autoclose": true, "ocr": true, "recent": true]
    @State private var feedback = ""
    @State private var keySet: Bool
    @State private var recordingShortcut: String?
    @State private var shortcutOverrides: [String: String] = [:]
    @State private var selectedSelectionTab = "行为"
    @State private var actions = ["翻译", "解释", "总结", "润色", "搜索"]
    @State private var templates = ["翻译", "总结", "润色", "解释"]
    @Environment(\.colorScheme) private var scheme
    private var p: Tokens.Palette { Tokens.palette(scheme) }

    init(model: SettingsPresentation) {
        _section = State(initialValue: model.section)
        _scenario = State(initialValue: model.scenario)
        _values = State(initialValue: model.values)
        _keySet = State(initialValue: model.scenario != .unconfigured)
        _selectedSelectionTab = State(initialValue: model.scenario == .actions ? "功能与应用" : "行为")
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(p.line).frame(width: Tokens.Size.stroke)
            VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                SettingsPageHeading(section: section)
                // A finite pane keeps ImageRenderer and the interactive layout identical.
                // Longer settings groups use explicit subpages, not a native scroll container.
                VStack(alignment: .leading, spacing: Tokens.Space.md) { sectionContent }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id(section)
                DesignRule()
                Text(feedback.isEmpty ? "设计预览 · 修改仅保留在当前面板" : feedback)
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(Tokens.Space.xl).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .font(Tokens.Typography.font()).foregroundStyle(p.foreground)
        .frame(width: Tokens.Size.settingsWidth, height: Tokens.Size.settingsHeight)
        .background(p.background, in: RoundedRectangle(cornerRadius: Tokens.Radius.window))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            SettingsBrand().padding(.vertical, Tokens.Space.md).padding(.horizontal, Tokens.Space.sm)
            ForEach(SettingsSection.allCases) { item in
                Button {
                    section = item; scenario = .normal; feedback = ""; recordingShortcut = nil
                } label: {
                    HStack(spacing: Tokens.Space.sm) {
                        Image(systemName: item.symbol).frame(width: Tokens.Size.icon)
                        Text(item.title)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, Tokens.Space.sm).frame(height: Tokens.Size.control)
                        .foregroundStyle(section == item ? p.accent : p.secondary)
                        .background(section == item ? p.selected : .clear,
                                    in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Text("设置预览")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.tertiary)
                .padding(Tokens.Space.sm)
        }.padding(Tokens.Space.md).frame(width: Tokens.Size.sidebarWidth).background(p.cardSecondary)
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .features: Notice(text: "功能总览请查看正式设置窗口。")
        case .general: generalPane
        case .input: inputPane
        case .translation: translationPane
        case .voice: voicePane
        case .selection: selectionPane
        case .screenshot: screenshotPane
        case .ai: aiPane
        case .templates: templatesPane
        case .shortcuts: shortcutsPane
        case .permissions: permissionsPane
        case .privacy: privacyPane
        case .about: aboutPane
        }
    }

    private func value(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: {
            values[key] = $0
            if key == "prompt" { scenario = .edited }
            feedback = "已更新当前预览"
        })
    }
    private func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { toggles[key] ?? false }, set: { toggles[key] = $0; feedback = "已更新当前预览" })
    }
    private func row<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Tokens.Space.md) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(title)
                if let detail { Text(detail).font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary) }
            }
            Spacer(minLength: Tokens.Space.sm)
            content()
        }.frame(minHeight: Tokens.Size.row)
    }
    private func toggle(_ title: String, _ key: String, detail: String? = nil) -> some View {
        row(title, detail: detail) { SettingsToggle(title: title, isOn: flag(key)) }
    }
    private func choice(_ title: String, _ key: String, _ options: [String]) -> some View {
        row(title) { DesignChoice(title: title, value: value(key), options: options) }
    }
    private func field(_ title: String, _ key: String) -> some View {
        row(title) { DesignEditableField(title: title, value: value(key)).frame(width: Tokens.Size.fieldWidth) }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignSectionTitle(title: "启动与外观")
            DesignCard {
                toggle("开机启动", "launch", detail: "登录后自动启动 RockType")
                DesignRule()
                toggle("在菜单栏显示 RockType", "menubar")
                toggle("菜单栏显示北京时间", "beijing", detail: "固定北京时间，不受本地时区影响")
                    .disabled(!(toggles["menubar"] ?? false))
                choice("外观", "theme", ["跟随系统", "浅色", "深色"])
            }
            DesignSectionTitle(title: "默认值")
            DesignCard { choice("搜索引擎", "search", ["Google", "Bing", "DuckDuckGo", "百度"]) }
        }
    }
    private var inputPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignSectionTitle(title: "输入方案")
            DesignCard {
                choice("默认方案", "scheme", ["全拼", "小鹤双拼"])
                toggle("常用模糊音", "fuzzy")
                toggle("拼写与按键纠错", "correction")
                row("中英切换", detail: "轻按 Shift；Shift + 字母不会误切换") { Kbd("Shift") }
            }
            DesignSectionTitle(title: "候选与译文")
            DesignCard {
                toggle("显示候选译文", "candidate", detail: "候选每页 5 项；译文不占编号")
                row("选用译文", detail: "跟随当前高亮候选，翻译不阻塞打字") { Kbd("Tab") }
            }
            Text("输出简体中文 · 右键候选可置顶、降权或删除学习词条。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
        }
    }
    private var translationPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignCard {
                choice("翻译引擎", "engine", ["Apple 离线优先", "AI 模型"])
                choice("目标语言", "target", ["自动（中 ⇄ 英）", "中文", "英文", "日文"])
                choice("翻译模型", "translation-model", ["默认模型", "example-text"])
            }
            DesignSectionTitle(title: "候选翻译")
            DesignCard {
                row("中英语言包", detail: "Apple 动态翻译需要 macOS 26") { Chip(text: "已就绪", tone: .ok) }
                row("离线兜底", detail: "精确匹配当前候选，不拼接未知句子") { Chip(text: "静态词条", tone: .neutral) }
                toggle("候选翻译允许使用 AI", "candidate-ai", detail: "默认关闭，仅开启后使用服务商连接")
            }
            Notice(text: "划词与截图：离线 → AI。候选翻译无结果时明确提示不可用。")
        }
    }
    private var voicePane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignCard {
                choice("识别模型", "model", ["0.6B · 8bit", "1.7B · 8bit"])
                Text("Qwen3-ASR · 本地识别；1.7B 占用更多内存。实际延迟与内存待实测。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                if scenario == .downloading {
                    DesignProgress(value: 0.42, label: "下载中 · 42% · 336 MB / 800 MB（示例）")
                    HStack {
                        Button("检查下载") { scenario = .installed; feedback = "示例模型下载与校验完成" }.buttonStyle(DesignButtonStyle(variant: .ghost))
                        Spacer()
                        Button("取消下载") { scenario = .normal; feedback = "已取消示例下载" }.buttonStyle(DesignButtonStyle()) }
                } else if scenario == .installed {
                    row("模型文件", detail: "约 800 MB（示例大小）· 校验通过") {
                        Chip(text: "已就绪", tone: .ok)
                        Button("删除") { scenario = .normal; feedback = "已移除预览中的模型状态" }.buttonStyle(DesignButtonStyle(variant: .danger))
                    }
                } else {
                    row("模型文件", detail: "约 800 MB（示例大小）· 未下载") {
                        Button("下载") { scenario = .downloading }.buttonStyle(DesignButtonStyle(variant: .primary))
                    }
                }
            }
            DesignCard {
                toggle("选中输入法时自动准备模型", "preload", detail: "只准备已下载模型，不开启麦克风")
                toggle("AI 润色语音结果", "polish", detail: keySet ? "失败时保留原识别结果" : "请先配置 AI 连接")
                    .disabled(!keySet)
                toggle("本地文字清理", "cleanup", detail: "整理口头填充词与标点，无需 AI")
                row("按住说话", detail: "松开结束，Esc 取消，不自动发送") { Kbd("Fn") }
            }
            Text("密码框或安全输入开启时，不填入语音。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
        }
    }
    private var selectionPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack { ForEach(["行为", "功能与应用"], id: \.self) { tab in
                Button(tab) { selectedSelectionTab = tab }.buttonStyle(DesignButtonStyle(variant: selectedSelectionTab == tab ? .primary : .ghost))
            } }
            if selectedSelectionTab == "行为" {
                DesignCard {
                    toggle("启用划词工具栏", "selection")
                    choice("出现方式", "trigger", ["划词即出", "仅快捷键"])
                    toggle("复制回退", "fallback", detail: "仅读取失败时使用，保护用户剪贴板的新内容")
                    toggle("功能窗口跟随工具栏", "follow")
                    toggle("点击外部自动关闭", "autoclose")
                    toggle("自动置顶", "autopin")
                    choice("透明度", "opacity", ["100%", "90%", "80%"])
                }
            } else {
                DesignCard {
                    VStack(spacing: Tokens.Space.xs) {
                        ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                            row(action) {
                                Button { actions.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }
                                    .buttonStyle(DesignButtonStyle(variant: .ghost)).disabled(index == 0).accessibilityLabel("上移" + action)
                                SettingsToggle(title: "启用" + action, isOn: Binding(get: { toggles["action-" + action] ?? true }, set: { toggles["action-" + action] = $0 }))
                            }
                        }
                    }
                }
                DesignCard {
                    VStack(spacing: Tokens.Space.xs) {
                        choice("应用筛选", "filter", ["黑名单", "白名单"])
                        field("应用列表", "apps")
                        choice("助手模型", "assistant-model", ["默认模型", "example-text"])
                    }
                }
            }
        }
    }
    private var screenshotPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignCard {
                row("开始截图", detail: "冻结屏幕后框选；Esc 取消") { Kbd("⌃1") }
                toggle("框选后显示文字识别入口", "ocr", detail: "文字识别在本机完成，不上传")
                choice("另存格式", "format", ["PNG", "JPEG"])
                row("完成动作", detail: "仅在选择另存为时写入文件") { Text("复制图片").foregroundStyle(p.secondary) }
            }
            DesignSectionTitle(title: "标注工具")
            DesignCard {
                Text("矩形 · 椭圆 · 箭头 · 画笔 · 马赛克 · 文字 · 序号")
                Text("支持撤销；按原始分辨率导出。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
            }
            Notice(text: "解释图片会发送你确认的图片，需要已验证支持图片的模型。")
        }
    }
    private var aiPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            if !canTestConnection {
                Text("尚未配置 · 支持 OpenAI Chat Completions 兼容接口")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.accent)
            }
            DesignCard {
                VStack(spacing: Tokens.Space.xs) {
                    field("服务名称", "name")
                    field("Base URL", "url")
                    row("API Key") {
                        Chip(text: keySet ? "已设置" : "未设置")
                        Button(keySet ? "更换" : "设置") {
                            feedback = "预览不接收真实密钥；已展示密钥设置状态"
                            keySet = true
                        }.buttonStyle(DesignButtonStyle(variant: .ghost))
                        if keySet {
                            Button("删除") { keySet = false; feedback = "已清除预览密钥状态" }.buttonStyle(DesignButtonStyle(variant: .ghost))
                        }
                    }
                    field("默认模型", "ai-model")
                    toggle("默认模型支持图片", "vision")
                    if !(toggles["vision"] ?? false) { field("视觉模型（可选）", "vision-model") }
                }
            }
            Text(values["url", default: ""].isEmpty ? "填写 Base URL 后显示实际请求地址" : "POST " + requestURL)
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary).lineLimit(1)
            HStack {
                DesignSectionTitle(title: "能力验证")
                Spacer()
                Button(scenario == .testing ? "查看测试结果" : "测试连接") {
                    scenario = scenario == .testing ? .mixed : .testing
                    feedback = "仅演示连接状态，不发送网络请求"
                }.buttonStyle(DesignButtonStyle()).disabled(!canTestConnection)
            }
            HStack(spacing: Tokens.Space.sm) {
                ForEach(Array(["文字", "流式", "图片", "取消"].enumerated()), id: \.offset) { index, name in
                    VStack(spacing: Tokens.Space.xs) {
                        Text(name).font(Tokens.Typography.font(Tokens.Typography.meta))
                        Chip(text: check(index).0, tone: check(index).1)
                    }.frame(maxWidth: .infinity).padding(.vertical, Tokens.Space.sm)
                        .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                }
            }
            if scenario == .mixed {
                Text("图片：模型不支持此输入。取消能力尚未验证。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.danger)
            }
        }
    }
    private var canTestConnection: Bool {
        keySet && !values["url", default: ""].isEmpty && !values["ai-model", default: ""].isEmpty
    }
    private var requestURL: String {
        var url = values["url", default: ""]
        while url.hasSuffix("/") { url.removeLast() }
        return url.hasSuffix("/chat/completions") ? url : url + "/chat/completions"
    }
    private func check(_ index: Int) -> (String, DesignTone) {
        switch scenario {
        case .testing: ("测试中", .accent)
        case .mixed: index < 2 ? ("可用", .ok) : index == 2 ? ("不可用", .danger) : ("未验证", .neutral)
        default: ("未验证", .neutral)
        }
    }
    private var templatesPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack(spacing: Tokens.Space.xs) {
                ForEach(templates, id: \.self) { name in
                    Button(name) {
                        values["template"] = name; values["template-name"] = name
                        values["prompt"] = name == "翻译" ? SettingsPresentation(section: .templates).values["prompt"] : "请对以下内容进行\(name)，保留原意。"
                    }.buttonStyle(DesignButtonStyle(variant: values["template"] == name ? .primary : .ghost))
                }
                Spacer(minLength: 0)
                Button { if !templates.contains("自定义") { templates.append("自定义") }; values["template"] = "自定义"; values["template-name"] = "自定义" }
                    label: { Image(systemName: "plus") }.buttonStyle(DesignButtonStyle()).accessibilityLabel("新增模板")
            }
            DesignCard {
                VStack(spacing: Tokens.Space.xs) {
                    field("名称", "template-name")
                    choice("图标", "template-icon", ["文", "✦", "Aa"])
                    choice("适用输入", "input-type", ["文字", "图片"])
                    choice("输出形式", "output", ["原文对照", "要点", "纯文本"])
                    choice("模型", "assistant-model", ["默认模型", "example-text", "example-vision"])
                }
            }
            HStack {
                DesignSectionTitle(title: scenario == .edited ? "提示词 · 已修改" : "提示词")
                Spacer()
                Button("恢复默认") {
                    values["prompt"] = SettingsPresentation(section: .templates).values["prompt"]
                    scenario = .normal; feedback = "已恢复当前预览的默认提示词"
                }.buttonStyle(DesignButtonStyle(variant: .ghost))
            }
            DesignEditableField(title: "提示词", value: value("prompt"), multiline: true)
            Text("{{target}} 为目标语言；内容快照作为用户消息单独传入。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
        }
    }
    private var shortcutsPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            if scenario == .conflict {
                Notice(text: "翻译选区与系统快捷键冲突，尚未生效。请重新设置。", tone: .warn)
            }
            DesignCard {
                VStack(spacing: Tokens.Space.xs) {
                    ForEach(SettingsFixtures.shortcuts, id: \.0) { title, key in
                        row(title) {
                            if title == "翻译选区" && scenario == .conflict { Image(systemName: "exclamationmark.triangle").foregroundStyle(p.warn) }
                            Button(recordingShortcut == title ? "按下组合键…" : shortcutOverrides[title] ?? key) {
                                recordingShortcut = title
                            }.buttonStyle(DesignButtonStyle()).disabled(key == "Shift" || key == "Tab")
                                .accessibilityLabel("设置" + title + "快捷键")
                                .onKeyPress { press in
                                    guard recordingShortcut == title else { return .ignored }
                                    if press.key == .escape { recordingShortcut = nil; return .handled }
                                    guard !press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .handled }
                                    let prefix = (press.modifiers.contains(.control) ? "⌃" : "") +
                                        (press.modifiers.contains(.option) ? "⌥" : "") +
                                        (press.modifiers.contains(.shift) ? "⇧" : "") +
                                        (press.modifiers.contains(.command) ? "⌘" : "")
                                    shortcutOverrides[title] = prefix + press.characters.uppercased()
                                    recordingShortcut = nil
                                    if title == "翻译选区" { scenario = .normal }
                                    feedback = "已更新快捷键预览，未注册系统快捷键"
                                    return .handled
                                }
                        }
                    }
                }
            }
            Text(recordingShortcut == nil ? "点击快捷键重新录制；输入法内 AI 仅在组词时触发。" : "按组合键完成录制，Esc 取消。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
        }
    }
    private var permissionsPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignSectionTitle(title: "RockType 权限")
            ForEach([("辅助功能", "读取选中文字，并在返回来源时切换窗口。"),
                     ("屏幕录制", "仅在你按下截图快捷键后读取屏幕。"),
                     ("麦克风", "仅在按住 Fn 时录音，松开立即结束。")], id: \.0) { title, detail in
                DesignCard {
                    row(title, detail: detail) { Chip(text: scenario == .denied ? "未授权" : "已授权", tone: scenario == .denied ? .warn : .ok) }
                    if scenario == .denied {
                        Button("打开系统设置") { feedback = "预览：在系统设置 → 隐私与安全性 → \(title) 中授权" }
                            .buttonStyle(DesignButtonStyle(variant: .ghost))
                    }
                }
            }
            Text("每次使用前重新检查；普通输入和本地静态词条无需这些权限。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
        }
    }
    private var privacyPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignCard {
                row("默认不保存内容", detail: "原文、截图与结果只在内存中；退出即清空。") { Image(systemName: "lock.shield").foregroundStyle(p.accent) }
                toggle("保留最近结果", "recent", detail: "最多 10 条，只保存在内存中。")
                row("清除当前内容", detail: "清空结果和追问上下文，不影响另存的图片。") {
                    Button("清除") { feedback = "当前预览内容已清空（没有读取或删除真实内容）" }
                        .buttonStyle(DesignButtonStyle(variant: .danger))
                }
            }
            DesignCard {
                Text("密码框与安全输入") .font(Tokens.Typography.font(weight: .medium))
                Text("不取词、不翻译、不调用 AI、不填入语音、不写缓存。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
            }
            DesignCard {
                row("本地诊断", detail: "只含动作、状态、耗时与脱敏错误；不含正文和密钥。") {
                    Button("导出诊断") { feedback = "诊断导出预览：未生成或写入文件" }.buttonStyle(DesignButtonStyle())
                }
            }
        }
    }
    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.lg) {
            DesignCard {
                Text("RockType").font(Tokens.Typography.font(Tokens.Typography.display, weight: .semibold))
                Text("设置预览 · 合成数据").foregroundStyle(p.secondary)
                Text("macOS 14 及以上 · Apple Silicon")
                DesignRule()
                Text("中文输入 · 双语候选 · 本地语音 · 划词与 AI · 截图")
                    .font(Tokens.Typography.font(Tokens.Typography.meta))
            }
            DesignCard {
                row("开源许可", detail: "主程序：MIT · 输入法：GPL v3") {
                    Button("查看说明") { feedback = "许可证见仓库 LICENSES 与 THIRD_PARTY_NOTICES" }.buttonStyle(DesignButtonStyle(variant: .ghost))
                }
                row("版本更新", detail: "更新来源以安装版本的配置为准。") { Chip(text: "待配置") }
            }
            Button("卸载 RockType…") { feedback = "安装版本中可选择保留用户数据；本预览不会删除程序或用户数据" }
                .buttonStyle(DesignButtonStyle(variant: .danger))
        }
    }
}

#endif
