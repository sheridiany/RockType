import AppKit
import CryptoKit
import Observation
import SwiftUI
import RoarkTCore
import RoarkTPlatform

@MainActor @Observable
final class ShellConnectionModel {
    private(set) var hasKey = false
    private(set) var configured = false
    private(set) var message = ""
    private(set) var testing = false
    private(set) var results = ["未验证", "未验证", "未验证", "未验证"]
    @ObservationIgnored private let keychain = Keychain()
    @ObservationIgnored private var testedKeyDigest: SHA256.Digest?
    @ObservationIgnored var readKey: (String) throws -> String? = { try Keychain().get(account: $0) }
    @ObservationIgnored var keyExists: (String) throws -> Bool = { try Keychain().exists(account: $0) }

    /// Refresh before trusting a probe: a key can also be replaced outside this settings view.
    func imageCapabilityVerified(connection: AIConnectionSettings, model: String) -> Bool {
        refresh(connection)
        let testedModel = connection.visionModel ?? (connection.defaultModelSupportsImages ? connection.defaultModel : "")
        return !testing && configured && testedKeyDigest != nil && results.count == 4
            && results[2] == "可用" && model == testedModel && !model.isEmpty
    }

    private func invalidateResults() {
        cancel()
        testedKeyDigest = nil
        results = Array(repeating: "未验证", count: 4)
    }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var secureInputWatch: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var configuration = AIConnectionSettings()
    @ObservationIgnored var runTests: (AIConnectionSettings, String) async -> [String] = { settings, secret in
        do {
            let result = try await AIConnectionTester(client: AIClient(connection: settings)).run(apiKey: secret)
            var labels = [result.text, result.streaming, result.image, result.cancellation].map(ShellConnectionModel.label)
            if result.text == .available, let latency = result.textLatency {
                labels[0] += String(format: " · %.2f 秒", latency)
            }
            return labels
        } catch { return Array(repeating: "未验证", count: 4) }
    }

    nonisolated private static func label(_ status: AIConnectionTestResult.Status) -> String {
        switch status {
        case .available: return "可用"
        case .unverified: return "未验证"
        case .unavailable(let error):
            let reason: String
            switch error {
            case .configuration: reason = "检查地址与模型"
            case .network: reason = "网络异常"
            case .unauthorized: reason = "检查密钥与权限"
            case .modelNotFound: reason = "模型不存在"
            case .rateLimited: reason = "限流，请稍后重试"
            case .server: reason = "服务异常"
            case .decoding: reason = "响应格式不兼容或中途断开"
            case .emptyResponse: reason = "模型未生成正文"
            case .outputLimit: reason = "输出预算不足，请换模型或缩短内容"
            case .timeout: reason = "请求超时"
            case .cancelled: reason = "请求已取消"
            case .http(let code): reason = "HTTP \(code)"
            case .responseTooLarge: reason = "响应过大"
            }
            return "不可用 · " + reason
        }
    }

    func refresh(_ settings: AIConnectionSettings) {
        if configuration != settings {
            invalidateResults()
            configuration = settings
        }
        do {
            let present = try keyExists(settings.id)
            if hasKey != present {
                cancel()
                results = Array(repeating: "未验证", count: 4)
            }
            if let testedKeyDigest {
                guard let secret = try readKey(settings.id),
                      SHA256.hash(data: Data(secret.utf8)) == testedKeyDigest else {
                    invalidateResults()
                    hasKey = present
                    configured = present && !settings.baseURL.isEmpty && !settings.defaultModel.isEmpty
                    return
                }
            }
            hasKey = present
            configured = hasKey && !settings.baseURL.isEmpty && !settings.defaultModel.isEmpty
            if !testing { message = hasKey ? "密钥已存入系统钥匙串" : "尚未设置密钥" }
        } catch {
            invalidateResults()
            hasKey = false
            configured = false
            message = "无法读取钥匙串状态，请检查钥匙串访问权限。"
        }
    }

    func saveKey(_ secret: String) -> Bool {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "密钥不能为空。"
            return false
        }
        invalidateResults()
        do {
            try keychain.set(secret, account: configuration.id)
            results = Array(repeating: "未验证", count: 4)
            refresh(configuration)
            return true
        } catch { message = "密钥保存失败，请检查钥匙串访问权限。"; return false }
    }

    func deleteKey() {
        invalidateResults()
        do {
            try keychain.delete(account: configuration.id)
            results = Array(repeating: "未验证", count: 4)
            refresh(configuration)
        } catch { message = "密钥删除失败，请检查钥匙串访问权限。" }
    }

    func test() {
        invalidateResults()
        guard !SecureInput.isSecureInputActive() else {
            message = "安全输入已开启，暂不发送连接测试。"
            return
        }
        let runTests = runTests
        do {
            guard let secret = try readKey(configuration.id), configured else {
                message = "请先填写连接地址、模型并设置密钥。"; return
            }
            testing = true
            results = Array(repeating: "测试中", count: 4)
            message = "正在发送合成测试内容，不会发送选中文字或用户文件。"
            let current = generation
            let config = configuration
            secureInputWatch = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    guard let self else { return }
                    if SecureInput.isSecureInputActive() {
                        self.cancel()
                        self.message = "安全输入已开启，连接测试已取消。"
                        return
                    }
                }
            }
            task = Task { [weak self] in
                let started = Date()
                try? await DiagnosticLog.shared.record(.init(action: .aiConnectionTest, status: .started))
                let result = await runTests(config, secret)
                guard let self, !Task.isCancelled, self.generation == current else { return }
                try? await DiagnosticLog.shared.record(.init(action: .aiConnectionTest,
                    status: result.contains(where: { $0.hasPrefix("不可用") }) ? .failed : .succeeded,
                    duration: Date().timeIntervalSince(started)))
                guard !Task.isCancelled, self.generation == current else { return }
                guard result.count == 4,
                      let currentSecret = try? self.readKey(config.id),
                      currentSecret == secret else { self.invalidateResults(); return }
                self.testedKeyDigest = SHA256.hash(data: Data(secret.utf8))
                self.results = result
                self.secureInputWatch?.cancel()
                self.secureInputWatch = nil
                self.testing = false
                self.message = "连接测试完成；结果仅对本次连接配置有效。"
                self.task = nil
            }
        } catch { message = "无法读取密钥，请检查钥匙串访问权限。" }
    }

    func cancel() {
        generation += 1
        secureInputWatch?.cancel()
        secureInputWatch = nil
        task?.cancel()
        task = nil
        if testing {
            Task { try? await DiagnosticLog.shared.record(.init(action: .aiConnectionTest, status: .cancelled)) }
            results = Array(repeating: "未验证", count: 4)
            message = "已取消连接测试。"
        }
        testing = false
    }
}

struct ShellConnectionView: View {
    let model: ShellConnectionModel
    @Binding var settings: AIConnectionSettings
    @State private var editingKey = false
    @State private var secret = ""
    @Environment(\.colorScheme) private var scheme
    private var p: Tokens.Palette { Tokens.palette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            if !model.configured {
                Notice(text: "填写服务地址、默认模型并设置密钥，即可开始使用 AI。未配置时，中文输入与本地 OCR 仍可使用。")
            }
            U4SectionTitle(title: "服务商连接")
            U4Card {
                field("服务名称", $settings.name)
                field("Base URL", $settings.baseURL)
                HStack {
                    Text("API Key"); Spacer(); Chip(text: model.hasKey ? "已设置" : "未设置")
                    Button(model.hasKey ? "更换" : "设置") { secret = ""; editingKey = true }
                    if model.hasKey { Button("删除") { model.deleteKey() } }
                }
                field("默认模型", $settings.defaultModel)
                U4Rule()
                SettingsControlRow("默认模型支持图片") {
                    U4Toggle(title: "默认模型支持图片", isOn: $settings.defaultModelSupportsImages)
                }
                field("视觉模型（可选）", Binding(get: { settings.visionModel ?? "" }, set: { settings.visionModel = $0.isEmpty ? nil : $0 }))
            }
            Text("OpenAI Chat Completions 兼容接口 · 测试会发送固定样本文字与图片。")
                .font(Tokens.Typography.font(Tokens.Typography.caption))
            HStack {
                U4SectionTitle(title: "能力验证"); Spacer()
                if model.testing { Button("取消测试") { model.cancel() } }
                else { Button("测试连接") { model.test() }.disabled(!model.configured) }
            }
            U4Card {
                ForEach(Array(["文字", "流式", "图片", "取消"].enumerated()), id: \.offset) { index, title in
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).frame(width: 44, alignment: .leading)
                        Spacer(minLength: Tokens.Space.sm)
                        Text(model.results[index])
                            .font(Tokens.Typography.font(Tokens.Typography.meta))
                            .foregroundStyle(model.results[index].hasPrefix("不可用") ? p.danger :
                                model.results[index] == "可用" ? p.ok : p.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    if index < 3 { U4Rule() }
                }
            }
            if !model.message.isEmpty {
                Text(model.message).font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
            }
        }
        .sheet(isPresented: $editingKey, onDismiss: { secret = "" }) {
            VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                Text("设置 API Key").font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                SecureField("API Key", text: $secret).textFieldStyle(.roundedBorder)
                Text("仅存系统钥匙串，不会写入设置文件或日志。")
                Text(model.message).font(Tokens.Typography.font(Tokens.Typography.caption))
                HStack {
                    Button("取消") { secret = ""; editingKey = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("保存") {
                        if model.saveKey(secret) { secret = ""; editingKey = false }
                    }.keyboardShortcut(.defaultAction).disabled(secret.isEmpty)
                }
            }.padding(Tokens.Space.xxl).frame(width: Tokens.Size.resultWidth)
        }
        .onAppear { model.refresh(settings) }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        SettingsControlRow(title) {
            TextField(title, text: text).textFieldStyle(.roundedBorder)
                .frame(width: Tokens.Size.fieldWidth).accessibilityLabel(title)
        }
    }
}
