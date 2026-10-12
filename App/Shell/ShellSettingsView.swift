import SwiftUI
import RoarkTCore

/// Settings-only presentation; all changes flow through the existing SettingsStore bindings.
struct ShellSettingsView: View {
    @Binding var settings: AppSettings
    let login: LoginItemController
    let connection: ShellConnectionModel
    let sections: ShellSettingsSections
    let persistenceMessage: String
    var persistenceFailed = false
    let exportDiagnostics: () -> Void
    var inputMethodSyncMessage: String? = nil
    var retryInputMethodSync: () -> Void = {}
    @FocusState private var focusedSection: SettingsSection?
    var clearCurrentContent: () -> Void = {}
    @Binding var section: SettingsSection
    @State private var language = LanguagePackModel()
    @Environment(\.colorScheme) private var scheme
    private var p: Tokens.Palette { Tokens.palette(scheme) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                SettingsBrand()
                    .padding(.vertical, Tokens.Space.md).padding(.horizontal, Tokens.Space.sm)
                ForEach(SettingsSection.allCases) { item in
                    Button { section = item } label: {
                        HStack(spacing: Tokens.Space.sm) {
                            Image(systemName: item.symbol).frame(width: Tokens.Size.icon)
                            Text(item.title)
                            Spacer(minLength: 0)
                        }.padding(.horizontal, Tokens.Space.sm).frame(height: 29)
                            .foregroundStyle(section == item ? p.foreground : p.secondary)
                            .background(section == item ? p.card : .clear,
                                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                    }.buttonStyle(.plain)
                        .focused($focusedSection, equals: item)
                        .focusEffectDisabled()
                        .accessibilityLabel(item.title + "设置")
                        .accessibilityHint("按空格或回车打开此分区")
                        .onKeyPress(.return) { section = item; return .handled }
                        .overlay {
                            RoundedRectangle(cornerRadius: Tokens.Radius.control)
                                .stroke(focusedSection == item ? p.focus : .clear,
                                        lineWidth: Tokens.Size.focusRing)
                                .allowsHitTesting(false)
                        }
                        .accessibilityAddTraits(section == item ? .isSelected : [])
                }
                Spacer(minLength: Tokens.Space.md)
                Text("修改自动保存")
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                    .padding(Tokens.Space.sm)
            }.padding(Tokens.Space.md).frame(width: Tokens.Size.sidebarWidth)
                .background(p.background)
                .accessibilityElement(children: .contain).accessibilityLabel("设置分区")
            Rectangle().fill(p.line).frame(width: Tokens.Size.stroke)
            VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                SettingsPageHeading(section: section)
                GeometryReader { geometry in
                    // Reserve the native scrollbar gutter even before it appears.
                    // macOS legacy scrollers otherwise clip the rightmost controls.
                    let gutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
                    ScrollView {
                        VStack(alignment: .leading, spacing: Tokens.Space.md) { content }
                            .frame(width: max(0, min(760, geometry.size.width - gutter - 2 * Tokens.Size.focusRing)), alignment: .leading)
                            .padding(Tokens.Size.focusRing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.id(section)
                DesignRule()
                Label(persistenceMessage, systemImage: persistenceFailed ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
                    .foregroundStyle(persistenceFailed ? p.danger : p.secondary).lineLimit(3)
            }.padding(Tokens.Space.xl).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.font(Tokens.Typography.font()).foregroundStyle(p.foreground).tint(p.accent)
            .frame(minWidth: Tokens.Size.settingsWidth, minHeight: Tokens.Size.settingsHeight)
            .background(p.background)
            .environment(\.settingsPresentation, true)
            .buttonStyle(DesignButtonStyle())
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .features: FeatureSettingsView(settings: $settings, permissions: sections.permissions,
            aiConfigured: inputAIConfigured, navigate: { section = $0 })
        case .general: general
        case .input: input
        case .translation: translation
        case .voice: SettingsFeatureContent(item: .voice, settings: $settings) { voice }
        case .selection: selection
        case .screenshot: screenshot
        case .ai: AIProviderSettingsView(model: connection, settings: $settings)
        case .templates: sections.templatesPane(settings: $settings, showAIConnection: { section = .ai })
        case .shortcuts:
            SettingsFeatureNotice(item: .selectionShortcuts, settings: $settings)
            sections.shortcutsPane(settings: $settings)
        case .permissions: sections.permissionsPane()
        case .privacy: privacy
        case .about: about
        }
    }

    private var inputAIConfigured: Bool {
        guard let route = try? AIProviderRouting.resolve(settings, task: .inputAI) else { return false }
        return !route.connection.baseURL.isEmpty && !route.model.isEmpty && (try? connection.keyExists(route.connection.id)) == true
    }

    private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
        SettingsControlRow(title, detail: value.wrappedValue ? "已启用" : "已关闭", symbol: toggleSymbol(title),
            status: value.wrappedValue ? .on : .off) { SettingsToggle(title: title, isOn: value) }
    }
    private func toggleSymbol(_ title: String) -> String {
        if title.contains("启动") { return "power" }
        if title.contains("菜单栏") { return "menubar.rectangle" }
        if title.contains("译文") || title.contains("翻译") { return "character.bubble" }
        if title.contains("窗口") || title.contains("置顶") { return "macwindow" }
        if title.contains("工具栏") { return "cursorarrow.rays" }
        if title.contains("结果") { return "clock.arrow.circlepath" }
        return "keyboard"
    }
    private func field(_ title: String, _ value: Binding<String>) -> some View {
        SettingsControlRow(title) {
            TextField(title, text: value).textFieldStyle(.roundedBorder)
                .frame(width: Tokens.Size.fieldWidth).accessibilityLabel(title)
        }
    }
    private func settingsPicker<Value: Hashable, Content: View>(_ title: String, selection: Binding<Value>,
                                                               @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsControlRow(title) {
            Picker(title, selection: selection, content: content).labelsHidden()
                .frame(width: Tokens.Size.fieldWidth).accessibilityLabel(title)
        }
    }
    private func optional(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }
    private func list(_ value: Binding<[String]>) -> Binding<String> {
        Binding(get: { value.wrappedValue.joined(separator: ", ") }, set: {
            value.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        })
    }

    private var general: some View {
        Group {
            DesignSectionTitle(title: "启动与菜单栏")
            DesignCard {
                toggle("开机启动", Binding(get: { login.enabled }, set: {
                    settings.general.launchAtLogin = login.setEnabled($0)
                }))
                Text(login.message).font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                if login.requiresApproval { Button("打开登录项设置") { login.openSystemSettings() } }
                DesignRule()
                toggle("在菜单栏显示 RockType", Binding(get: { settings.general.menuBarIcon ?? false },
                                                        set: { settings.general.menuBarIcon = $0 }))
                DesignRule()
                toggle("菜单栏显示北京时间", $settings.general.showBeijingTime)
                    .disabled(!settings.general.showsMenuBarItem)
                Text("不显示时，可从输入法菜单的“设置…”或启动台打开 RockType。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
            }
            DesignSectionTitle(title: "外观与搜索")
            DesignCard {
                settingsPicker("外观", selection: $settings.general.appearance) {
                    Text("跟随系统").tag(GeneralSettings.Appearance.system)
                    Text("浅色").tag(GeneralSettings.Appearance.light)
                    Text("深色").tag(GeneralSettings.Appearance.dark)
                }
                Text("界面语言：简体中文")
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                DesignRule()
                settingsPicker("搜索引擎", selection: $settings.selection.searchEngine) {
                    Text("Google").tag("https://www.google.com/search?q={query}")
                    Text("Bing").tag("https://www.bing.com/search?q={query}")
                    Text("DuckDuckGo").tag("https://duckduckgo.com/?q={query}")
                    Text("百度").tag("https://www.baidu.com/s?wd={query}")
                }
            }
        }
    }
    private var input: some View {
        Group {
            SettingsFeatureNotices(items: [.candidateTranslation, .inputMethodAI], settings: $settings)
            if let message = inputMethodSyncMessage {
                Notice(text: message, tone: .warn)
                Button("重试同步", action: retryInputMethodSync)
            }
            DesignSectionTitle(title: "输入方案与纠错")
            DesignCard {
                settingsPicker("默认方案", selection: $settings.input.scheme) {
                    Text("全拼").tag(InputSettings.Scheme.pinyin)
                    Text("小鹤双拼").tag(InputSettings.Scheme.flypy)
                }
                DesignRule()
                toggle("常用模糊音", $settings.input.fuzzyPinyin)
                DesignRule()
                toggle("简拼", $settings.input.abbreviatedPinyin)
                DesignRule()
                toggle("拼写与按键纠错", $settings.input.spellingCorrection)
            }
            DesignSectionTitle(title: "候选与输入习惯")
            DesignCard {
                toggle("轻按 Shift 切换中英", $settings.input.shiftTogglesLanguage)
                DesignRule()
                toggle("显示输入模式提示", $settings.input.showModeIndicator)
                DesignRule()
                toggle("显示候选译文", $settings.input.candidateTranslation)
                    .disabled(!settings.input.candidateTranslation)
                DesignRule()
                toggle("英文补全", $settings.input.englishCompletion)
                Text("每页最多 5 个候选 · Tab 选用译文 · 简体输出")
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
            }
            DesignSectionTitle(title: "输入法内 AI")
            DesignCard {
                InputAISettingsSection(settings: $settings)
                    .disabled(!settings.enabledFeatures.inputMethodAI)
                    .opacity(settings.enabledFeatures.inputMethodAI ? 1 : 0.48)
                Button("配置 AI 连接") { section = .ai }
            }
            Text("更改自动同步，当前组词结束后生效。尚未添加输入法？")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
            Button("前往权限与输入法检查") { section = .permissions }
                .buttonStyle(DesignButtonStyle(variant: .ghost))
        }
    }
    private var translation: some View {
        Group {
            DesignSectionTitle(title: "引擎与目标语言")
            DesignCard {
                settingsPicker("翻译引擎", selection: $settings.translation.engine) {
                    Text("Apple 离线优先").tag(TranslationSettings.Engine.offlineFirst)
                    Text("AI 模型").tag(TranslationSettings.Engine.ai)
                }
                DesignRule()
                settingsPicker("目标语言", selection: $settings.translation.targetLanguage) {
                    Text("自动（中 ⇄ 英）").tag("auto"); Text("中文").tag("zh-Hans")
                    Text("英文").tag("en"); Text("日文").tag("ja")
                }
                SettingsMore {
                    field("翻译模型（空为默认）", optional($settings.translation.model))
                    toggle("候选翻译允许使用 AI", $settings.translation.allowCandidateAI)
                        .disabled(!settings.input.candidateTranslation)
                }
            }
            DesignSectionTitle(title: "离线语言包")
            DesignCard { LanguagePackStepView(model: language) }
            Notice(text: "动态离线翻译需要 macOS 26 和语言包。候选静态词条按原文精确匹配；主动触发输入法 AI 时，当前文字会发送到所配置的服务商。")
        }
    }
    private var voice: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignSectionTitle(title: "本地识别与文字处理")
            VoiceSettingsPane(settings: $settings.voice, aiConfigured: connection.configured)
            HStack {
                Button("检查麦克风与辅助功能权限") { section = .permissions }
                if !connection.configured { Button("配置 AI 润色") { section = .ai } }
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
        }
    }
    private var selection: some View {
        Group {
            SettingsFeatureNotices(items: [.selectionToolbar, .selectionShortcuts], settings: $settings)
            Notice(text: "松开鼠标后显示工具栏；快捷键立即处理选区。关闭跟随后会记住结果窗口位置，置顶窗口可并行保留。")
            DesignSectionTitle(title: "工具栏与结果窗口")
            DesignCard {
                Group {
                    settingsPicker("出现方式", selection: $settings.selection.trigger) {
                        Text("划词即出").tag(SelectionSettings.Trigger.selection)
                        Text("仅快捷键").tag(SelectionSettings.Trigger.shortcutOnly)
                    }
                    DesignRule()
                    toggle("工具栏仅显示图标", Binding(get: { settings.selection.toolbarIconsOnly ?? false },
                        set: { settings.selection.toolbarIconsOnly = $0 }))
                    DesignRule()
                    toggle("减少工具栏误弹", Binding(get: { settings.selection.suppressAccidentalPopups ?? true },
                        set: { settings.selection.suppressAccidentalPopups = $0 }))
                    Text("忽略不足两个字符的选区、按住修饰键拖选和拖选时滚动；快捷键不受影响。")
                        .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                }.disabled(!settings.enabledFeatures.selectionToolbar)
                    .opacity(settings.enabledFeatures.selectionToolbar ? 1 : 0.48)
                SettingsMore(title: "更多 · 结果窗口") {
                    toggle("功能窗口跟随工具栏", $settings.selection.followToolbar)
                    toggle("点击外部自动关闭", $settings.selection.automaticallyClose)
                    toggle("自动置顶", $settings.selection.automaticallyPin)
                    HStack { Text("透明度"); Slider(value: $settings.selection.windowOpacity, in: 0.5...1).accessibilityLabel("结果窗口透明度")
                        Text(settings.selection.windowOpacity, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 40, alignment: .trailing) }
                    field("助手模型（空为默认）", optional($settings.selection.assistantModel))
                }.disabled(!settings.enabledFeatures.selectionToolbar && !settings.enabledFeatures.selectionShortcuts)
            }
            SettingsMore(title: "更多 · 生效应用与操作顺序") {
                DesignSectionTitle(title: "生效应用")
                DesignCard {
                    settingsPicker("应用筛选", selection: $settings.selection.applicationFilter) {
                        Text("黑名单").tag(SelectionSettings.ApplicationFilter.blacklist)
                        Text("白名单").tag(SelectionSettings.ApplicationFilter.whitelist)
                    }
                    if settings.selection.applicationFilter == .blacklist {
                        field("排除应用 ID", list($settings.selection.excludedApplications))
                    } else {
                        field("允许应用 ID", list($settings.selection.includedApplications))
                        if settings.selection.includedApplications.isEmpty {
                            Notice(text: "尚未添加允许的应用，划词工具栏暂不会出现。")
                        }
                    }
                    Text("多个应用 Bundle ID 用英文逗号分隔；Finder 默认排除。")
                        .font(Tokens.Typography.font(Tokens.Typography.caption))
                }
                DesignSectionTitle(title: "工具栏操作 · 按显示顺序")
                DesignCard {
                    if settings.selection.toolbarActions.isEmpty {
                        Text("还没有工具栏操作。可在“操作模板”中添加。")
                        Button("管理操作模板") { section = .templates }
                    }
                    ForEach(Array(settings.selection.toolbarActions.enumerated()), id: \.element) { index, id in
                        HStack {
                            Text(settings.templates.first(where: { $0.id == id })?.name ?? (id == "search" ? "搜索" : id))
                            Spacer()
                            Button { settings.selection.toolbarActions.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0).accessibilityLabel("上移" + (settings.templates.first(where: { $0.id == id })?.name ?? id))
                            Button { settings.selection.toolbarActions.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == settings.selection.toolbarActions.count - 1).accessibilityLabel("下移" + (settings.templates.first(where: { $0.id == id })?.name ?? id))
                            SettingsToggle(title: "启用" + (settings.templates.first(where: { $0.id == id })?.name ?? (id == "search" ? "搜索" : id)), isOn: Binding(get: { !settings.selection.disabledActions.contains(id) }, set: {
                                settings.selection.disabledActions.removeAll { $0 == id }
                                if !$0 { settings.selection.disabledActions.append(id) }
                            }))
                        }
                    }
                }
            }.disabled(!settings.enabledFeatures.selectionToolbar)
                .opacity(settings.enabledFeatures.selectionToolbar ? 1 : 0.48)
        }
    }
    private var screenshot: some View {
        Group {
            SettingsFeatureNotices(items: [.screenshot, .screenshotHistory, .pinning], settings: $settings)
            Group {
                DesignSectionTitle(title: "复制与导出")
                ScreenshotOutputSettings(settings: $settings.screenshot)
                DesignCard {
                    settingsPicker("另存格式", selection: $settings.screenshot.format) {
                        Text("PNG").tag(ScreenshotSettings.Format.png); Text("JPEG").tag(ScreenshotSettings.Format.jpeg)
                    }
                }
                SettingsMore(title: "更多 · 标注默认样式") { ScreenshotStyleSettings(settings: $settings.screenshot) }
            }.disabled(!settings.enabledFeatures.screenshot).opacity(settings.enabledFeatures.screenshot ? 1 : 0.48)
            Group { ScreenshotHistorySettings(settings: $settings.screenshot) }
                .disabled(!settings.enabledFeatures.screenshotHistory).opacity(settings.enabledFeatures.screenshotHistory ? 1 : 0.48)
            DesignSectionTitle(title: "贴图历史")
            DesignCard {
                Stepper(value: Binding(get: { min(50, max(0, settings.screenshot.pinHistoryLimit ?? 10)) },
                                       set: { settings.screenshot.pinHistoryLimit = $0 }), in: 0...50) {
                    Text("最近关闭最多保留 \(min(50, max(0, settings.screenshot.pinHistoryLimit ?? 10))) 张")
                }.accessibilityLabel("贴图历史数量")
                Text("设为 0 不保留；调小数量会立即移除最早的历史。总计最多 64 MB，仅在本次运行内保留，退出或清除当前内容后清空。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
            }
            .disabled(!settings.enabledFeatures.pinning).opacity(settings.enabledFeatures.pinning ? 1 : 0.48)
            DesignSectionTitle(title: "本地文字识别")
            DesignCard {
                OCRLanguageSettings(languages: $settings.screenshot.ocrLanguages)
            }.disabled(!settings.enabledFeatures.screenshot).opacity(settings.enabledFeatures.screenshot ? 1 : 0.48)
            Button("检查屏幕录制权限") { section = .permissions }
                .buttonStyle(DesignButtonStyle(variant: .ghost))
            DesignCard {
                Text("图片理解会发送你确认的图片，需要支持图片的 AI 模型。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
            }
        }
    }
    private var privacy: some View {
        Group {
            DesignSectionTitle(title: "本次会话")
            DesignCard {
                toggle("保留最近结果", $settings.privacy.keepRecentResultsInMemory)
                Text("最多 10 条，只保存在内存中。退出或关闭开关后清空最近结果。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                DesignRule()
                SettingsControlRow("清除当前内容", detail: "清空结果与追问，不删除另存的图片；已开启磁盘保存的截图历史请在历史面板清空。") {
                    Button("清除", action: clearCurrentContent).buttonStyle(DesignButtonStyle(variant: .danger))
                }
            }
            DesignSectionTitle(title: "隐私保护")
            DesignCard {
                Label("密码框与安全输入", systemImage: "lock.shield").fontWeight(.medium)
                Text("不取词、不翻译、不调用 AI、不填入语音、不写缓存。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                DesignRule()
                Text("密钥仅存系统钥匙串。诊断只含动作类型、状态、耗时与脱敏错误，不包含原文、截图或密钥。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                Button("导出诊断…", action: exportDiagnostics).buttonStyle(DesignButtonStyle())
            }
        }
    }
    private var about: some View {
        Group {
            DesignCard {
                Text("RockType").font(Tokens.Typography.font(Tokens.Typography.display, weight: .semibold))
                Text("版本 " + AboutDocuments.version(Bundle.main.infoDictionary ?? [:]))
                Text("macOS 14 及以上 · Apple Silicon")
                DesignRule()
                Text("主程序：MIT · 输入法：GPL v3")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                UpdateSettingsView()
            }
            AboutLegalLinks()
            DesignSectionTitle(title: "维护")
            DesignCard {
                SettingsControlRow("诊断", detail: "导出不含正文与密钥的本地诊断。") {
                    Button("导出…", action: exportDiagnostics)
                }
                DesignRule()
                SettingsControlRow("卸载 RockType", detail: "下一步可选择是否保留用户数据。") {
                    Button("卸载…") { UninstallController.confirm() }
                        .buttonStyle(DesignButtonStyle(variant: .danger))
                }
            }
        }
    }
}
