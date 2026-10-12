import SwiftUI
import RoarkTCore
import RoarkTPlatform

/// Provider selection swaps preferences only. Each id has its own Keychain account.
struct AIProviderSettingsView: View {
    let model: ShellConnectionModel
    @Binding var settings: AppSettings
    @State private var deleting: String?
    @State private var adding = false
    @Environment(\.colorScheme) private var scheme
    private var profiles: [AIConnectionSettings] { AIProviderRouting.providers(settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.lg) {
            DesignSectionTitle(title: "服务商 · 选择默认连接")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                ForEach(profiles, id: \.id) { profile in
                    Button {
                        model.cancel(); AIProviderRouting.select(profile.id, in: &settings); model.refresh(settings.ai)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "server.rack").font(.system(size: 21)).frame(width: 28)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.name.isEmpty ? "未命名服务商" : profile.name).fontWeight(.medium).lineLimit(1)
                                Text(profile.id == settings.ai.id ? "默认连接" : "点击设为默认")
                                    .font(.system(size: 11)).foregroundStyle(Tokens.palette(scheme).secondary)
                            }
                            Spacer(minLength: 0)
                            if profile.id == settings.ai.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.palette(scheme).ok) }
                        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }.buttonStyle(SettingsProviderTileStyle(selected: profile.id == settings.ai.id))
                        .accessibilityLabel(profile.name + (profile.id == settings.ai.id ? "，默认连接" : "，设为默认连接"))
                }
                Button { adding.toggle() } label: {
                    Label("添加服务商", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(SettingsProviderTileStyle(selected: false))
            }
            if adding {
                DesignCard {
                    SettingsControlRow("OpenAI 兼容服务", detail: "填写服务地址与自己的密钥", symbol: "network") {
                        Button("添加") { addProvider(local: false) }.accessibilityLabel("添加兼容服务")
                    }
                    DesignRule()
                    SettingsControlRow("本机服务", detail: "连接本机运行的兼容接口", symbol: "desktopcomputer") {
                        Button("添加") { addProvider(local: true) }.accessibilityLabel("添加本机服务")
                    }
                    Button("收起") { adding = false }.buttonStyle(DesignButtonStyle(variant: .ghost))
                }
            }
            ShellConnectionView(model: model, settings: $settings.ai)
            SettingsMore(title: "更多 · 备用模型与移除连接") {
                DesignCard {
                    SettingsControlRow("失败时备用模型", symbol: "arrow.triangle.branch") {
                        TextField("留空则不切换模型", text: Binding(get: { settings.ai.fallbackModel ?? "" },
                            set: { settings.ai.fallbackModel = AIProviderRouting.nonempty($0) })).textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 216).accessibilityLabel("失败时备用模型")
                    }
                    Text("仅在未生成正文且遇到临时故障时，尝试同一服务商的备用模型。图片能力需单独验证。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if AIProviderRouting.nonempty(settings.ai.fallbackModel) != nil {
                        Text("备用图片能力：" + model.fallbackImageResult).font(.caption).foregroundStyle(.secondary)
                    }
                    Menu("移除其他连接") {
                        ForEach(profiles.filter { $0.id != settings.ai.id }, id: \.id) { profile in
                            Button(profile.name.isEmpty ? "未命名服务商" : profile.name) { deleting = profile.id }
                        }
                    }.disabled(profiles.count < 2)
                }
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
    private func addProvider(local: Bool) {
        model.cancel()
        var profile = AIConnectionSettings()
        profile.id = UUID().uuidString
        profile.name = local ? "本机服务" : "新的服务商"
        profile.baseURL = local ? "http://127.0.0.1:3425/v1" : ""
        profile.defaultModel = AIProviderRouting.recommendedModel
        profile.defaultModelSupportsImages = true
        settings.aiProviders = (settings.aiProviders ?? []) + [profile]
        AIProviderRouting.select(profile.id, in: &settings)
        model.refresh(settings.ai); adding = false
    }

}

struct AITaskRoutingSettings: View {
    @Binding var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignSectionTitle(title: "按任务选择服务与模型")
            DesignCard {
                ForEach(AITask.allCases, id: \.self) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsControlRow(task.title, symbol: "arrow.triangle.branch") {
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
                        .labelsHidden().frame(maxWidth: 216).accessibilityLabel(task.title + "服务商")
                        }
                        if settings.aiTaskRoutes?[task.rawValue] != nil {
                            TextField(task == .image ? "留空使用该服务商视觉模型" : "留空使用该服务商默认模型", text: Binding(get: { settings.aiTaskRoutes?[task.rawValue]?.model ?? "" }, set: {
                                settings.aiTaskRoutes?[task.rawValue]?.model = AIProviderRouting.nonempty($0)
                            })).textFieldStyle(.roundedBorder).accessibilityLabel(task.title + "模型")
                        }
                    }
                    if task != AITask.allCases.last { DesignRule() }
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

private struct SettingsProviderTileStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        let p = Tokens.palette(scheme)
        configuration.label.padding(14)
            .foregroundStyle(p.foreground)
            .background(configuration.isPressed ? p.bubble : p.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(focused ? p.focus : selected ? p.accent : p.line, lineWidth: focused ? 3 : selected ? 1 : 0.5))
    }
}
