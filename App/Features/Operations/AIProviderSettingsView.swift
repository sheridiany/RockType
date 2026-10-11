import SwiftUI
import RoarkTCore
import RoarkTPlatform

/// Provider selection swaps preferences only. Each id has its own Keychain account.
struct AIProviderSettingsView: View {
    let model: ShellConnectionModel
    @Binding var settings: AppSettings
    @State private var deleting: String?
    private var profiles: [AIConnectionSettings] { AIProviderRouting.providers(settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.lg) {
            HStack {
                Picker("默认服务商", selection: Binding(get: { settings.ai.id }, set: {
                    model.cancel(); AIProviderRouting.select($0, in: &settings); model.refresh(settings.ai)
                })) {
                    ForEach(profiles, id: \.id) { profile in
                        Text(profile.name.isEmpty ? "未命名服务商" : profile.name).tag(profile.id)
                    }
                }
                Button("添加") {
                    var profile = AIConnectionSettings()
                    profile.id = UUID().uuidString
                    profile.name = "新的服务商"
                    profile.baseURL = "http://127.0.0.1:3425/v1"
                    profile.defaultModel = AIProviderRouting.recommendedModel
                    profile.defaultModelSupportsImages = true
                    settings.aiProviders = (settings.aiProviders ?? []) + [profile]
                    AIProviderRouting.select(profile.id, in: &settings)
                    model.refresh(settings.ai)
                }
                Menu("移除") {
                    ForEach(profiles.filter { $0.id != settings.ai.id }, id: \.id) { profile in
                        Button(profile.name.isEmpty ? "未命名服务商" : profile.name) { deleting = profile.id }
                    }
                }.disabled(profiles.count < 2)
            }
            ShellConnectionView(model: model, settings: $settings.ai)
            HStack {
                Text("失败时备用模型")
                TextField("留空则不切换模型", text: Binding(get: { settings.ai.fallbackModel ?? "" },
                    set: { settings.ai.fallbackModel = AIProviderRouting.nonempty($0) }))
                    .textFieldStyle(.roundedBorder)
            }
            Text("仅在没有生成正文且出现临时故障时，使用你填写的同一服务商备用模型。可填写 claude/claude-haiku-5-5；不会自动添加或跨服务商发送。图片仍需单独验证能力。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(.secondary)
            if AIProviderRouting.nonempty(settings.ai.fallbackModel) != nil {
                Text("备用图片能力：" + model.fallbackImageResult).font(.caption).foregroundStyle(.secondary)
            }
            AITaskRoutingSettings(settings: $settings)
        }
        .onChange(of: settings.ai) { _, value in model.refresh(value) }
        .confirmationDialog("移除此服务商？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("移除配置", role: .destructive) {
                if let deleting { AIProviderRouting.remove(deleting, from: &settings) }
                deleting = nil
            }
        } message: {
            Text("钥匙串密钥保留，可先切换到此服务商并删除密钥。引用此服务商的任务将停止发送，直到重新选择。")
        }
    }
}

struct AITaskRoutingSettings: View {
    @Binding var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            Text("按任务选择服务与模型").fontWeight(.medium)
            ForEach(AITask.allCases, id: \.self) { task in
                VStack(alignment: .leading, spacing: 6) {
                    Picker(task.title, selection: Binding(get: { settings.aiTaskRoutes?[task.rawValue]?.providerID ?? "" }, set: { id in
                        if settings.aiTaskRoutes == nil { settings.aiTaskRoutes = [:] }
                        settings.aiTaskRoutes?[task.rawValue] = id.isEmpty ? nil : AITaskRoute(providerID: id)
                    })) {
                        Text("跟随默认服务商").tag("")
                        ForEach(AIProviderRouting.providers(settings), id: \.id) { profile in
                            Text(profile.name.isEmpty ? "未命名服务商" : profile.name).tag(profile.id)
                        }
                        if let id = settings.aiTaskRoutes?[task.rawValue]?.providerID,
                           !AIProviderRouting.providers(settings).contains(where: { $0.id == id }) {
                            Text("服务商已移除，请重新选择").tag(id)
                        }
                    }
                    if settings.aiTaskRoutes?[task.rawValue] != nil {
                        TextField(task == .image ? "留空使用该服务商视觉模型" : "留空使用该服务商默认模型", text: Binding(get: { settings.aiTaskRoutes?[task.rawValue]?.model ?? "" }, set: {
                            settings.aiTaskRoutes?[task.rawValue]?.model = AIProviderRouting.nonempty($0)
                        })).textFieldStyle(.roundedBorder).accessibilityLabel(task.title + "模型")
                    }
                }
            }
            Text("图片默认跟随服务商的视觉模型（未单独指定时跟随默认模型）。模板单独指定的模型仍优先。连接和图片验证请先将对应服务商选为默认，再测试。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(.secondary)
        }
    }
}

@MainActor enum AIProviderAvailability {
    static func configured(_ settings: AppSettings) -> Bool {
        AIProviderRouting.providers(settings).contains {
            !$0.baseURL.isEmpty && !$0.defaultModel.isEmpty && (try? Keychain().exists(account: $0.id)) == true
        }
    }
}
