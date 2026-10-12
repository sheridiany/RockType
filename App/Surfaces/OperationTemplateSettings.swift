import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RoarkTCore

/// Atomic edits keep toolbar membership consistent and reject stale sheet drafts.
@MainActor enum OperationTemplateEdits {
    enum Failure: Error { case invalid(String), changed }

    static func optionalModel(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func effectiveModel(_ template: OperationTemplate, settings: AppSettings) -> String {
        (try? AIProviderRouting.resolve(settings, task: template.input == .image ? .image : (template.id == "translate" ? .translation : .assistant), modelOverride: template.model).model) ?? ""
    }

    static func validation(_ template: OperationTemplate) -> String? {
        if template.id.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) == nil
            || ["copy", "search"].contains(template.id) || template.id.hasPrefix("screenshot-") { return "动作标识无效或已保留。" }
        if template.name.count > 80 || template.prompt.utf8.count > 16_384 || (template.model?.utf8.count ?? 0) > 256 { return "名称最多 80 字，提示词最多 16 KB，模型名称最多 256 字节。" }
        if let shortcut = template.shortcut, shortcut.key == nil || shortcut.modifiers.intersection([.control, .option, .command]).isEmpty || !shortcut.modifiers.subtracting([.control, .option, .command, .shift]).isEmpty { return "快捷键需使用 Control、Option 或 Command 加按键。" }
        if template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写模板名称。" }
        if NSImage(systemSymbolName: template.icon, accessibilityDescription: nil) == nil { return "图标名称无效，请填写有效的 SF Symbols 名称。" }
        if template.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写提示词。" }
        if OperationTemplate.defaults.contains(where: { $0.id == template.id }), template.input != .text {
            return "内置模板用于文字输入。图片操作请新建自定义模板。"
        }
        return nil
    }

    static func save(_ draft: OperationTemplate, replacing original: OperationTemplate?, settings: inout AppSettings) throws {
        if let message = validation(draft) { throw Failure.invalid(message) }
        var item = draft
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.model = optionalModel(item.model)
        if let original {
            guard item.id == original.id, let index = settings.templates.firstIndex(where: { $0.id == original.id }),
                  settings.templates[index] == original else { throw Failure.changed }
            settings.templates[index] = item
        } else {
            guard settings.templates.count < 100 else { throw Failure.invalid("最多保存 100 个动作，请先删除不再使用的动作。") }
            guard !settings.templates.contains(where: { $0.id == item.id }),
                  !OperationTemplate.defaults.contains(where: { $0.id == item.id }), item.id != "search" else { throw Failure.changed }
            settings.templates.append(item)
            if !settings.selection.toolbarActions.contains(item.id) { settings.selection.toolbarActions.append(item.id) }
            settings.selection.disabledActions.removeAll { $0 == item.id }
        }
    }

    static func delete(_ original: OperationTemplate, settings: inout AppSettings) throws {
        guard !OperationTemplate.defaults.contains(where: { $0.id == original.id }),
              settings.templates.first(where: { $0.id == original.id }) == original else { throw Failure.changed }
        settings.templates.removeAll { $0.id == original.id }
        settings.selection.toolbarActions.removeAll { $0 == original.id }
        settings.selection.disabledActions.removeAll { $0 == original.id }
    }

    static func imageNotice(_ template: OperationTemplate, settings: AppSettings) -> String? {
        guard template.input == .image else { return nil }
        let model = effectiveModel(template, settings: settings)
        let connection = (try? AIProviderRouting.resolve(settings, task: .image, modelOverride: template.model).connection) ?? settings.ai
        let declared = !model.isEmpty && (model == optionalModel(connection.visionModel)
            || (model == optionalModel(connection.defaultModel) && connection.defaultModelSupportsImages))
        return declared
            ? "此模型已配置为图片模型，仍需在 AI 连接中验证图片能力。图片模板仅用于图片入口，不能处理文字选区。"
            : "当前模型未配置为图片模型。可保存模板，但执行前需在 AI 连接中配置并验证视觉模型；文字选区不能执行图片模板。"
    }
}

struct OperationTemplateSettings: View {
    @Binding var settings: AppSettings
    let showAIConnection: () -> Void
    var hotkeys: HotkeyCenter? = nil
    @State private var editing: Edit?
    @State private var deleting: OperationTemplate?
    @State private var notice: String?
    @State private var importing: OperationActionArchive.Document?

    private struct Edit: Identifiable {
        let id = UUID()
        let original: OperationTemplate?
        var draft: OperationTemplate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Text("保存后，下一次操作使用新提示词。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta))
                Spacer()
                Button("新增模板", systemImage: "plus") {
                    editing = Edit(original: nil, draft: OperationTemplate(name: "", icon: "sparkles", prompt: ""))
                }.buttonStyle(DesignButtonStyle(variant: .primary))
            }
            HStack {
                Button("导入 JSON…", action: importActions)
                Button("导出 JSON…", action: exportActions)
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
            if let notice { Notice(text: notice) }
            if settings.templates.isEmpty { Notice(text: "还没有操作模板，点击“新增模板”开始。") }
            DesignSectionTitle(title: "动作列表")
            DesignCard {
                ForEach(settings.templates) { template in
                    SettingsControlRow(template.name.isEmpty ? "未命名模板" : template.name,
                        detail: (isBuiltIn(template) ? "内置" : "自定义") + " · " + (template.input == .text ? "文字" : "图片") + " · " + modelLabel(template),
                        symbol: NSImage(systemSymbolName: template.icon, accessibilityDescription: nil) == nil ? "sparkles" : template.icon) {
                        Button("编辑") { editing = Edit(original: template, draft: template) }.accessibilityLabel("编辑" + template.name)
                        Menu {
                            Button("上移") { move(template.id, -1) }.disabled(settings.templates.first?.id == template.id)
                            Button("下移") { move(template.id, 1) }.disabled(settings.templates.last?.id == template.id)
                            if !isBuiltIn(template) { Button("删除", role: .destructive) { deleting = template } }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
                            .accessibilityLabel(template.name + "更多操作")
                    }
                    if template.id != settings.templates.last?.id { DesignRule() }
                }
            }
            SettingsMore(title: "更多 · 模型默认值") {
            OperationModelSettings(settings: $settings, showAIConnection: showAIConnection)
            }
        }
        .sheet(item: $editing) { edit in
            OperationTemplateEditor(initial: edit.draft, original: edit.original, settings: $settings,
                                    showAIConnection: { editing = nil; showAIConnection() }, hotkeys: hotkeys)
        }
        .alert("导入动作？", isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } })) {
            Button("取消", role: .cancel) { importing = nil }
            Button("导入并合并") {
                guard let document = importing else { return }
                do { var next = settings; try OperationActionArchive.apply(document, to: &next); settings = next; notice = "动作已导入。请检查快捷键注册状态。" }
                catch { notice = "导入未完成，请检查文件格式和动作内容。" }
                importing = nil
            }
        } message: { Text("将导入 \(importing?.actions.count ?? 0) 个动作。同标识动作会更新，其他动作保留；文件中的快捷键将在保存后注册。") }
        .alert("删除自定义模板？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                guard let original = deleting else { return }
                do {
                    var next = settings
                    try OperationTemplateEdits.delete(original, settings: &next)
                    settings = next; notice = "模板已删除，工具栏中的对应操作也已移除。"
                } catch { notice = "模板已被其他设置操作修改，请检查后重试。" }
                deleting = nil
            }
        } message: { Text("删除后会同时从工具栏移除。内置模板不受影响。") }
    }

    private func move(_ id: String, _ offset: Int) {
        var next = settings; OperationTemplateEdits.move(id, by: offset, settings: &next); settings = next
    }
    private func importActions() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 256 * 1024 else { throw OperationActionArchive.Failure.invalid }
            importing = try OperationActionArchive.decode(Data(contentsOf: url))
        } catch { notice = "无法导入。请选择不超过 256 KB、版本为 1 的动作 JSON 文件。" }
    }
    private func exportActions() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "RockType-actions.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try OperationActionArchive.export(settings).write(to: url, options: .atomic); notice = "动作已导出。文件只包含动作定义及入口设置。" }
        catch OperationActionArchive.Failure.invalid { notice = "动作文件超过限制或含无效动作，请将总量精简至 256 KB、最多 100 个动作后重试。" }
        catch { notice = "导出未完成，请检查保存位置和写入权限。" }
    }
    private func isBuiltIn(_ template: OperationTemplate) -> Bool {
        OperationTemplate.defaults.contains { $0.id == template.id }
    }
    private func modelLabel(_ template: OperationTemplate) -> String {
        let model = OperationTemplateEdits.effectiveModel(template, settings: settings)
        return model.isEmpty ? "尚未指定模型" : "模型：" + model
    }
}

struct OperationTemplateEditor: View {
    @State private var draft: OperationTemplate
    let original: OperationTemplate?
    @Binding var settings: AppSettings
    let showAIConnection: () -> Void
    let hotkeys: HotkeyCenter?
    @State private var toolbarEnabled: Bool
    @State private var recording = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(initial: OperationTemplate, original: OperationTemplate?, settings: Binding<AppSettings>,
         showAIConnection: @escaping () -> Void, hotkeys: HotkeyCenter? = nil) {
        self.hotkeys = hotkeys
        _toolbarEnabled = State(initialValue: initial.input == .text && (original == nil || (settings.wrappedValue.selection.toolbarActions.contains(initial.id) && !settings.wrappedValue.selection.disabledActions.contains(initial.id))))
        _draft = State(initialValue: initial); self.original = original
        _settings = settings; self.showAIConnection = showAIConnection
    }
    private var modelRoute: AIProviderRouting.Resolved? { try? AIProviderRouting.resolve(settings, task: draft.input == .image ? .image : (draft.id == "translate" ? .translation : .assistant)) }
    private var shortcutLabel: String {
        guard let shortcut = draft.shortcut else { return "录制快捷键" }
        return (shortcut.modifiers.contains(.control) ? "⌃" : "") + (shortcut.modifiers.contains(.option) ? "⌥" : "") + (shortcut.modifiers.contains(.shift) ? "⇧" : "") + (shortcut.modifiers.contains(.command) ? "⌘" : "") + (shortcut.key?.uppercased() ?? "")
    }
    private var builtIn: OperationTemplate? { OperationTemplate.defaults.first { $0.id == draft.id } }
    private let icons = ["sparkles": "星光", "text.bubble": "对话", "character.bubble": "翻译",
                         "text.alignleft": "段落", "pencil": "铅笔", "questionmark.bubble": "解释",
                         "photo": "图片", "list.bullet": "列表", "doc.text": "文档"]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            Text(original == nil ? "新增操作模板" : "编辑操作模板")
                .font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.md) {
                    TextField("模板名称", text: $draft.name).textFieldStyle(.roundedBorder).accessibilityLabel("模板名称")
                    Picker("图标", selection: $draft.icon) {
                        ForEach(Array(Set(Array(icons.keys) + [draft.icon])).sorted(), id: \.self) { icon in
                            Label(icons[icon] ?? "当前图标", systemImage: icon).tag(icon)
                        }
                    }
                    Picker("适用输入", selection: $draft.input) {
                        Text("文字").tag(OperationTemplate.Input.text)
                        Text("图片").tag(OperationTemplate.Input.image)
                    }.disabled(builtIn != nil)
                        .onChange(of: draft.input) { _, input in if input == .image { toolbarEnabled = false } }
                    Picker("输出形式", selection: $draft.output) {
                        Text("原文对照").tag(OperationTemplate.Output.comparison)
                        Text("纯文本").tag(OperationTemplate.Output.text)
                        Text("Markdown").tag(OperationTemplate.Output.markdown)
                    }
                    OperationModelField(title: "此模板", model: $draft.model,
                                        inherited: modelRoute?.model ?? "", connection: modelRoute?.connection ?? settings.ai)
                    if let message = OperationTemplateEdits.imageNotice(draft, settings: settings) {
                        Notice(text: message, tone: .warn)
                        Button("配置并验证图片模型", action: showAIConnection)
                        Text("前往 AI 连接将关闭本次未保存的编辑。")
                            .font(Tokens.Typography.font(Tokens.Typography.caption))
                    }
                    Toggle("用于划词工具栏", isOn: $toolbarEnabled).disabled(draft.input == .image)
                    Toggle("用于截图预览", isOn: Binding(get: { draft.showInScreenshot == true }, set: { draft.showInScreenshot = $0 }))
                    HStack {
                        Text("全局快捷键")
                        Button(recording ? "按下组合键…" : shortcutLabel) { recording = true; hotkeys?.beginTemplateRecording(draft.id) }
                        Button("清除") { draft.shortcut = nil }
                    }
                    if recording {
                        ShortcutRecorder(voiceOnly: false, onRecord: { draft.shortcut = $0; recording = false; hotkeys?.cancelRecording() }, onCancel: { recording = false; hotkeys?.cancelRecording() }).frame(height: 1)
                    }
                    if let status = hotkeys?.templateStatuses[draft.id] { Text(status.text).font(.caption) }
                    Text("默认不设置快捷键。文字动作处理当前选区；图片动作先框选截图，再按发送确认设置处理。")
                        .font(Tokens.Typography.font(Tokens.Typography.caption))
                    Text("提示词").font(Tokens.Typography.font(weight: .medium))
                    DesignTextArea(title: "模板提示词", text: $draft.prompt)
                    if draft.id == "translate" {
                        Text("{{target}} 会替换为所选目标语言。自定义翻译提示词用于 AI 翻译，Apple 离线翻译不读取提示词。")
                            .font(Tokens.Typography.font(Tokens.Typography.caption))
                    }
                    if let builtIn {
                        Button("恢复默认提示词") { draft.prompt = builtIn.prompt; failure = nil }
                        Button("恢复默认动作") { draft = builtIn; toolbarEnabled = true; failure = nil }
                    }
                    if let message = failure ?? OperationTemplateEdits.validation(draft) { Notice(text: message, tone: .warn) }
                }.padding(Tokens.Size.focusRing)
            }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    do {
                        var next = settings
                        try OperationTemplateEdits.save(draft, replacing: original, settings: &next)
                        OperationTemplateEdits.setToolbar(toolbarEnabled && draft.input == .text, id: draft.id, settings: &next)
                        settings = next; dismiss()
                    } catch OperationTemplateEdits.Failure.invalid(let message) { failure = message }
                    catch { failure = "模板已在其他位置更改。请取消编辑，重新打开后再修改。" }
                }.keyboardShortcut(.defaultAction).disabled(OperationTemplateEdits.validation(draft) != nil)
                    .buttonStyle(DesignButtonStyle(variant: .primary))
            }
        }.padding(Tokens.Space.xl).frame(width: 480, height: 600)
            .modifier(DesignSurface())
            .onDisappear { if recording { hotkeys?.cancelRecording() } }
    }
}
