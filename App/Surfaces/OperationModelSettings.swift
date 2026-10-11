import SwiftUI
import RoarkTCore

/// Preferences only: these controls never fetch models or send content.
struct OperationModelSettings: View {
    @Binding var settings: AppSettings
    let showAIConnection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignCard {
                Text("按功能指定模型").font(Tokens.Typography.font(weight: .medium))
                Text("所有模型使用同一个 AI 服务商连接。留空时使用连接的默认模型；模板单独指定的模型优先。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta))
                OperationModelField(title: "翻译", model: $settings.translation.model,
                                    inherited: settings.ai.defaultModel, connection: settings.ai)
                OperationModelField(title: "总结、润色与解释", model: $settings.selection.assistantModel,
                                    inherited: settings.ai.defaultModel, connection: settings.ai)
                Text("离线优先时，翻译模型用于离线失败后的 AI 路径；离线成功时仍使用 Apple Translation。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
            }
            Button("配置 AI 连接与模型", action: showAIConnection)
                .buttonStyle(DesignButtonStyle(variant: .secondary))
        }
    }
}

struct OperationModelField: View {
    let title: String
    @Binding var model: String?
    let inherited: String
    let connection: AIConnectionSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack {
                Text(title)
                Spacer()
                TextField("跟随默认模型", text: Binding(get: { model ?? "" }, set: {
                    model = OperationTemplateEdits.optionalModel($0)
                }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: Tokens.Size.fieldWidth)
                .accessibilityLabel(title + "模型")
                Menu {
                    Button("跟随默认模型") { model = nil }
                    ForEach(knownModels, id: \.self) { name in Button(name) { model = name } }
                } label: { Image(systemName: "chevron.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: Tokens.Space.xl)
                    .accessibilityLabel("选择" + title + "模型")
            }
            let effective = OperationTemplateEdits.optionalModel(model) ?? OperationTemplateEdits.optionalModel(inherited)
            Text(effective.map { "当前模型：" + $0 } ?? "尚未指定模型，请配置 AI 连接。")
                .font(Tokens.Typography.font(Tokens.Typography.caption))
                .foregroundStyle(Tokens.palette(scheme).secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var knownModels: [String] {
        Array(Set([connection.defaultModel, connection.visionModel ?? "", model ?? ""]
            .compactMap { OperationTemplateEdits.optionalModel($0) })).sorted()
    }
}
