import AppKit
import SwiftUI
import RoarkTCore

/// Atomic edits keep toolbar membership consistent and reject stale sheet drafts.
@MainActor enum OperationTemplateEdits {
    enum Failure: Error { case invalid(String), changed }

    static func optionalModel(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func effectiveModel(_ template: OperationTemplate, settings: AppSettings) -> String {
        optionalModel(template.model)
            ?? optionalModel(template.id == "translate" ? settings.translation.model : settings.selection.assistantModel)
            ?? optionalModel(settings.ai.defaultModel) ?? ""
    }

    static func validation(_ template: OperationTemplate) -> String? {
        if template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写模板名称。" }
        if NSImage(systemSymbolName: template.icon, accessibilityDescription: nil) == nil { return "请选择有效的 SF Symbols 图标。" }
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
        let declared = !model.isEmpty && (model == optionalModel(settings.ai.visionModel)
            || (model == optionalModel(settings.ai.defaultModel) && settings.ai.defaultModelSupportsImages))
        return declared
            ? "此模型已配置为图片模型，仍需在 AI 连接中验证图片能力。图片模板仅用于图片入口，不能处理文字选区。"
            : "当前模型未配置为图片模型。可保存模板，但执行前需在 AI 连接中配置并验证视觉模型；文字选区不能执行图片模板。"
    }
}

struct OperationTemplateSettings: View {
    @Binding var settings: AppSettings
    let showAIConnection: () -> Void
    @State private var editing: Edit?
    @State private var deleting: OperationTemplate?
    @State private var notice: String?

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
            if let notice { Notice(text: notice) }
            if settings.templates.isEmpty { Notice(text: "还没有操作模板，点击“新增模板”开始。") }
            ForEach(settings.templates) { template in
                DesignCard {
                    HStack {
                        Label(template.name.isEmpty ? "未命名模板" : template.name,
                              systemImage: NSImage(systemSymbolName: template.icon, accessibilityDescription: nil) == nil ? "sparkles" : template.icon)
                        Spacer()
                        Chip(text: isBuiltIn(template) ? "内置" : "自定义")
                        Button("编辑") { editing = Edit(original: template, draft: template) }
                            .accessibilityLabel("编辑" + template.name)
                        if !isBuiltIn(template) {
                            Button("删除", role: .destructive) { deleting = template }
                                .accessibilityLabel("删除" + template.name)
                        }
                    }.buttonStyle(DesignButtonStyle(variant: .ghost))
                    Text((template.input == .text ? "文字" : "图片") + " · " + modelLabel(template))
                        .font(Tokens.Typography.font(Tokens.Typography.caption))
                    Text(template.prompt.isEmpty ? "尚未填写提示词" : template.prompt)
                        .lineLimit(2).font(Tokens.Typography.font(Tokens.Typography.meta))
                }
            }
            OperationModelSettings(settings: $settings, showAIConnection: showAIConnection)
        }
        .sheet(item: $editing) { edit in
            OperationTemplateEditor(initial: edit.draft, original: edit.original, settings: $settings,
                                    showAIConnection: { editing = nil; showAIConnection() })
        }
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
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(initial: OperationTemplate, original: OperationTemplate?, settings: Binding<AppSettings>,
         showAIConnection: @escaping () -> Void) {
        _draft = State(initialValue: initial); self.original = original
        _settings = settings; self.showAIConnection = showAIConnection
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
                    Picker("输出形式", selection: $draft.output) {
                        Text("原文对照").tag(OperationTemplate.Output.comparison)
                        Text("纯文本").tag(OperationTemplate.Output.text)
                        Text("Markdown").tag(OperationTemplate.Output.markdown)
                    }
                    OperationModelField(title: "此模板", model: $draft.model,
                                        inherited: (draft.id == "translate" ? settings.translation.model : settings.selection.assistantModel)
                                            ?? settings.ai.defaultModel, connection: settings.ai)
                    if let message = OperationTemplateEdits.imageNotice(draft, settings: settings) {
                        Notice(text: message, tone: .warn)
                        Button("配置并验证图片模型", action: showAIConnection)
                        Text("前往 AI 连接将关闭本次未保存的编辑。")
                            .font(Tokens.Typography.font(Tokens.Typography.caption))
                    }
                    Text("提示词").font(Tokens.Typography.font(weight: .medium))
                    DesignTextArea(title: "模板提示词", text: $draft.prompt)
                    if draft.id == "translate" {
                        Text("{{target}} 会替换为所选目标语言。自定义翻译提示词用于 AI 翻译，Apple 离线翻译不读取提示词。")
                            .font(Tokens.Typography.font(Tokens.Typography.caption))
                    }
                    if let builtIn {
                        Button("恢复默认提示词") { draft.prompt = builtIn.prompt; failure = nil }
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
                        settings = next; dismiss()
                    } catch OperationTemplateEdits.Failure.invalid(let message) { failure = message }
                    catch { failure = "模板已在其他位置更改。请取消编辑，重新打开后再修改。" }
                }.keyboardShortcut(.defaultAction).disabled(OperationTemplateEdits.validation(draft) != nil)
                    .buttonStyle(DesignButtonStyle(variant: .primary))
            }
        }.padding(Tokens.Space.xl).frame(width: 480, height: 600)
            .modifier(DesignSurface())
    }
}
