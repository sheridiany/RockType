import AppKit
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
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var configuration = AIConnectionSettings()
    @ObservationIgnored var runTests: ((AIConnectionSettings, String) async -> [String])?

    func refresh(_ settings: AIConnectionSettings) {
        if configuration != settings {
            cancel()
            results = Array(repeating: "未验证", count: 4)
            configuration = settings
        }
        do {
            hasKey = try keychain.exists(account: settings.id)
            configured = hasKey && !settings.baseURL.isEmpty && !settings.defaultModel.isEmpty
            if !testing { message = hasKey ? "密钥已存入系统钥匙串" : "尚未设置密钥" }
        } catch {
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
        cancel()
        do {
            try keychain.set(secret, account: configuration.id)
            results = Array(repeating: "未验证", count: 4)
            refresh(configuration)
            return true
        } catch { message = "密钥保存失败，请检查钥匙串访问权限。"; return false }
    }

    func deleteKey() {
        cancel()
        do {
            try keychain.delete(account: configuration.id)
            results = Array(repeating: "未验证", count: 4)
            refresh(configuration)
        } catch { message = "密钥删除失败，请检查钥匙串访问权限。" }
    }

    func test() {
        cancel()
        guard let runTests else { message = "连接测试等待集成。"; return }
        do {
            guard let secret = try keychain.get(account: configuration.id), configured else {
                message = "请先填写连接地址、模型并设置密钥。"; return
            }
            testing = true
            results = Array(repeating: "测试中", count: 4)
            message = "正在发送合成测试内容，不会发送选中文字或用户文件。"
            let current = generation
            let config = configuration
            task = Task { [weak self] in
                let result = await runTests(config, secret)
                guard let self, !Task.isCancelled, self.generation == current else { return }
                self.results = result
                self.testing = false
                self.message = "连接测试完成；结果仅对本次连接配置有效。"
                self.task = nil
            }
        } catch { message = "无法读取密钥，请检查钥匙串访问权限。" }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        if testing {
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

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            U4Card {
                field("服务名称", $settings.name)
                field("Base URL", $settings.baseURL)
                HStack {
                    Text("API Key"); Spacer(); Chip(text: model.hasKey ? "已设置" : "未设置")
                    Button(model.hasKey ? "更换" : "设置") { secret = ""; editingKey = true }
                    if model.hasKey { Button("删除") { model.deleteKey() } }
                }
                field("默认模型", $settings.defaultModel)
                Toggle("默认模型支持图片", isOn: $settings.defaultModelSupportsImages)
                field("视觉模型（可选）", Binding(get: { settings.visionModel ?? "" }, set: { settings.visionModel = $0.isEmpty ? nil : $0 }))
            }
            Text("OpenAI Chat Completions 兼容接口 · 测试会发送固定样本文字与图片。")
                .font(Tokens.Typography.font(Tokens.Typography.caption))
            HStack {
                Text("能力验证"); Spacer()
                if model.testing { Button("取消测试") { model.cancel() } }
                else { Button("测试连接") { model.test() }.disabled(!model.configured) }
            }
            HStack(spacing: Tokens.Space.sm) {
                ForEach(Array(["文字", "流式", "图片", "取消"].enumerated()), id: \.offset) { index, title in
                    VStack(spacing: Tokens.Space.xs) {
                        Text(title)
                        Text(model.results[index]).font(Tokens.Typography.font(Tokens.Typography.caption))
                    }.frame(maxWidth: .infinity)
                }
            }
            Text(model.message).font(Tokens.Typography.font(Tokens.Typography.caption))
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
        HStack { Text(title); Spacer(); TextField(title, text: text).textFieldStyle(.roundedBorder)
                .frame(width: Tokens.U4.fieldWidth) }
    }
}
