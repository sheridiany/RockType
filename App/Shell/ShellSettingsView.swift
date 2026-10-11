import SwiftUI
import RoarkTCore

/// Production settings use the same U4 components, with bindings supplied by SettingsStore.
struct ShellSettingsView: View {
    @Binding var settings: AppSettings
    let login: LoginItemController
    let connection: ShellConnectionModel
    let sections: ShellSettingsSections
    let persistenceMessage: String
    let exportDiagnostics: () -> Void
    var inputMethodSyncMessage: String? = nil
    var retryInputMethodSync: () -> Void = {}
    @FocusState private var focusedSection: SettingsSection?
    @State private var keyboardNavigation = false
    var clearCurrentContent: () -> Void = {}
    @Binding var section: SettingsSection
    @State private var language = LanguagePackModel()
    @Environment(\.colorScheme) private var scheme
    private var p: Tokens.Palette { Tokens.palette(scheme) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("RockType").font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                    .padding(Tokens.Space.md)
                ForEach(SettingsSection.allCases) { item in
                    Button { section = item } label: {
                        HStack(spacing: Tokens.Space.sm) {
                            Image(systemName: item.symbol).frame(width: Tokens.Size.icon)
                            Text(item.title)
                            Spacer(minLength: 0)
                        }.padding(.horizontal, Tokens.Space.sm).frame(height: Tokens.Size.control)
                            .foregroundStyle(section == item ? p.accent : p.secondary)
                            .background(section == item ? p.selected : .clear,
                                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                    }.buttonStyle(.plain)
                        .focused($focusedSection, equals: item)
                        .focusEffectDisabled()
                        .overlay {
                            RoundedRectangle(cornerRadius: Tokens.Radius.control)
                                .stroke(keyboardNavigation && focusedSection == item ? p.focus : .clear,
                                        lineWidth: Tokens.Size.focusRing)
                                .allowsHitTesting(false)
                        }
                        .accessibilityAddTraits(section == item ? .isSelected : [])
                }
                Spacer()
            }.padding(Tokens.Space.md).frame(width: Tokens.U4.sidebarWidth)
            Rectangle().fill(p.line).frame(width: Tokens.Size.stroke)
            VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                Text(section.title).font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                Text(section.detail).font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.md) { content }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Tokens.Size.focusRing)
                }
                U4Rule()
                Text(persistenceMessage).font(Tokens.Typography.font(Tokens.Typography.caption))
                    .foregroundStyle(p.secondary).lineLimit(2)
            }.padding(Tokens.Space.xl).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.font(Tokens.Typography.font()).foregroundStyle(p.foreground).tint(p.accent)
            .frame(minWidth: Tokens.Size.settingsWidth, minHeight: Tokens.Size.settingsHeight)
            .background(p.background)
            .background(SettingsSidebarInteraction { keyboard in
                keyboardNavigation = keyboard
                if !keyboard { focusedSection = nil }
            })
            .onChange(of: focusedSection) { _, focused in
                if keyboardNavigation, let focused { section = focused }
            }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .general: general
        case .input: input
        case .translation: translation
        case .voice: voice
        case .selection: selection
        case .screenshot: screenshot
        case .ai: ShellConnectionView(model: connection, settings: $settings.ai)
        case .templates: sections.templatesPane(settings: $settings, showAIConnection: { section = .ai })
        case .shortcuts: sections.shortcutsPane(settings: $settings)
        case .permissions: sections.permissionsPane()
        case .privacy: privacy
        case .about: about
        }
    }

    private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
        HStack { Text(title); Spacer(); U4Toggle(title: title, isOn: value) }.frame(minHeight: Tokens.Size.row)
    }
    private func field(_ title: String, _ value: Binding<String>) -> some View {
        HStack { Text(title); Spacer(); TextField(title, text: value).textFieldStyle(.roundedBorder)
                .frame(width: Tokens.U4.fieldWidth) }.frame(minHeight: Tokens.Size.row)
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
            U4Card {
                toggle("开机启动", Binding(get: { login.enabled }, set: {
                    settings.general.launchAtLogin = login.setEnabled($0)
                }))
                Text(login.message).font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                if login.requiresApproval { Button("打开登录项设置") { login.openSystemSettings() } }
                toggle("菜单栏显示北京时间", $settings.general.showBeijingTime)
                Picker("外观", selection: $settings.general.appearance) {
                    Text("跟随系统").tag(GeneralSettings.Appearance.system)
                    Text("浅色").tag(GeneralSettings.Appearance.light)
                    Text("深色").tag(GeneralSettings.Appearance.dark)
                }
                Text("界面语言：简体中文；其他语言即将推出。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
            }
            U4Card {
                Picker("搜索引擎", selection: $settings.selection.searchEngine) {
                    Text("Google").tag("https://www.google.com/search?q={query}")
                    Text("Bing").tag("https://www.bing.com/search?q={query}")
                    Text("DuckDuckGo").tag("https://duckduckgo.com/?q={query}")
                    Text("百度").tag("https://www.baidu.com/s?wd={query}")
                }
            }
            Button("重新运行首次引导") { sections.showOnboarding() }
        }
    }
    private var input: some View {
        Group {
            Notice(text: inputMethodSyncMessage ?? "保存后自动同步到输入法。Rime 配置更改将在当前组词结束后重新部署；默认方案在空闲时应用，仍可从系统输入菜单选择全拼或双拼。")
            if inputMethodSyncMessage != nil { Button("重试同步", action: retryInputMethodSync) }
            U4Card {
                Picker("默认方案", selection: $settings.input.scheme) {
                    Text("全拼").tag(InputSettings.Scheme.pinyin)
                    Text("小鹤双拼").tag(InputSettings.Scheme.flypy)
                }
                toggle("常用模糊音", $settings.input.fuzzyPinyin)
                toggle("简拼", $settings.input.abbreviatedPinyin)
                toggle("拼写与按键纠错", $settings.input.spellingCorrection)
                toggle("轻按 Shift 切换中英", $settings.input.shiftTogglesLanguage)
                toggle("显示输入模式提示", $settings.input.showModeIndicator)
                toggle("显示候选译文", $settings.input.candidateTranslation)
                toggle("英文补全", $settings.input.englishCompletion)
                Text("每页最多 5 个候选 · Tab 选用译文 · 简体输出")
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
            }
        }
    }
    private var translation: some View {
        Group {
            U4Card {
                Picker("翻译引擎", selection: $settings.translation.engine) {
                    Text("Apple 离线优先").tag(TranslationSettings.Engine.offlineFirst)
                    Text("AI 模型").tag(TranslationSettings.Engine.ai)
                }
                Picker("目标语言", selection: $settings.translation.targetLanguage) {
                    Text("自动（中 ⇄ 英）").tag("auto"); Text("中文").tag("zh-Hans")
                    Text("英文").tag("en"); Text("日文").tag("ja")
                }
                field("翻译模型（空为默认）", optional($settings.translation.model))
                toggle("候选翻译允许使用 AI", $settings.translation.allowCandidateAI)
            }
            U4Card { LanguagePackStepView(model: language) }
            Notice(text: "动态离线翻译需 macOS 26；候选静态词条按原文精确匹配。候选 AI、指定目标语言以及划词与截图翻译即将推出；当前候选始终使用离线中英互译。")
        }
    }
    private var voice: some View {
        VoiceSettingsPane(settings: $settings.voice, aiConfigured: connection.configured)
    }
    private var selection: some View {
        Group {
            Notice(text: "划词工具栏与功能窗口即将推出。以下偏好在重启后保留。")
            U4Card {
                Picker("出现方式", selection: $settings.selection.trigger) {
                    Text("划词即出").tag(SelectionSettings.Trigger.selection)
                    Text("仅快捷键").tag(SelectionSettings.Trigger.shortcutOnly)
                }
                toggle("功能窗口跟随工具栏", $settings.selection.followToolbar)
                toggle("点击外部自动关闭", $settings.selection.automaticallyClose)
                toggle("自动置顶", $settings.selection.automaticallyPin)
                HStack { Text("透明度"); Slider(value: $settings.selection.windowOpacity, in: 0.5...1)
                    Text(settings.selection.windowOpacity, format: .percent.precision(.fractionLength(0))) }
                field("助手模型（空为默认）", optional($settings.selection.assistantModel))
            }
            U4Card {
                Picker("应用筛选", selection: $settings.selection.applicationFilter) {
                    Text("黑名单").tag(SelectionSettings.ApplicationFilter.blacklist)
                    Text("白名单").tag(SelectionSettings.ApplicationFilter.whitelist)
                }
                field("排除应用 ID", list($settings.selection.excludedApplications))
                field("允许应用 ID", list($settings.selection.includedApplications))
                Text("多个应用 Bundle ID 用英文逗号分隔；Finder 默认排除。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
            }
            U4Card {
                ForEach(Array(settings.selection.toolbarActions.enumerated()), id: \.element) { index, id in
                    HStack {
                        Text(settings.templates.first(where: { $0.id == id })?.name ?? (id == "search" ? "搜索" : id))
                        Spacer()
                        Button { settings.selection.toolbarActions.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0).accessibilityLabel("上移操作")
                        U4Toggle(title: "启用操作", isOn: Binding(get: { !settings.selection.disabledActions.contains(id) }, set: {
                            settings.selection.disabledActions.removeAll { $0 == id }
                            if !$0 { settings.selection.disabledActions.append(id) }
                        }))
                    }
                }
            }
        }
    }
    private var screenshot: some View {
        Group {
            Notice(text: "截图、标注与本地 OCR 即将推出。快捷键默认为 ⌃1；仅主动另存时写入文件。")
            U4Card {
                Picker("另存格式", selection: $settings.screenshot.format) {
                    Text("PNG").tag(ScreenshotSettings.Format.png); Text("JPEG").tag(ScreenshotSettings.Format.jpeg)
                }
                field("OCR 语言", list($settings.screenshot.ocrLanguages))
            }
        }
    }
    private var privacy: some View {
        U4Card {
            toggle("会话内保留最近结果", $settings.privacy.keepRecentResultsInMemory)
            Text("最多 10 条，不落盘；退出或关闭此开关后清空最近结果。")
            Button("清除当前内容", action: clearCurrentContent)
            U4Rule()
            Text("密码框 / Secure Input：不取词、不翻译、不调用 AI、不填入语音、不写缓存。")
            Text("密钥仅存系统钥匙串。诊断仅含动作类型、状态、耗时与脱敏错误。")
        }
    }
    private var about: some View {
        Group {
            U4Card {
                Text("RockType").font(Tokens.Typography.font(Tokens.Typography.display, weight: .semibold))
                Text("版本 " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"))
                Text("macOS 14 及以上 · Apple Silicon")
                U4Rule()
                Text("主 App：MIT · 输入法：GPL v3，按进程隔离。")
                UpdateSettingsView()
                Button("卸载 RockType…") { UninstallController.confirm() }
            }
            Button("导出诊断…", action: exportDiagnostics)
        }
    }
}
