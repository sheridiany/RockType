import SwiftUI
import RoarkTCore
import RoarkTPlatform

struct InputAISettingsSection: View {
    @Binding var settings: AppSettings
    @State private var recording = false
    @State private var notice: String?
    private var preferences: Binding<InputAISettings> {
        Binding(get: { settings.input.inputAI ?? InputAISettings() }, set: { settings.input.inputAI = $0 })
    }
    private var route: AIProviderRouting.Resolved? { try? AIProviderRouting.resolve(settings, task: .inputAI) }
    private var configured: Bool {
        guard let route else { return false }
        return !route.connection.baseURL.isEmpty && (try? Keychain().exists(account: route.connection.id)) == true
    }
    var body: some View {
        Section("输入法内 AI") {
            Toggle("启用输入法内 AI", isOn: preferences.enabled)
                .disabled(!configured && !preferences.wrappedValue.enabled)
            if let route {
                Text("当前模型：" + route.model).foregroundStyle(.secondary)
            }
            if !configured {
                Text("先在 AI 连接中选择服务商并设置密钥，再启用输入法内 AI。")
                    .foregroundStyle(.secondary)
            }
            Picker("等待上限", selection: preferences.timeout) {
                Text("15 秒").tag(15.0)
                Text("30 秒").tag(30.0)
                Text("60 秒").tag(60.0)
                Text("90 秒").tag(90.0)
                if ![15.0, 30, 60, 90].contains(preferences.wrappedValue.timeout) {
                    Text("当前 \(Int(preferences.wrappedValue.timeout)) 秒").tag(preferences.wrappedValue.timeout)
                }
            }
            HStack {
                Text("改写 / 润色 / 翻译")
                Spacer()
                Button(recording ? "按下组合键…" : label(preferences.wrappedValue.shortcut)) { recording = true; notice = nil }
                Button("恢复默认") { set(InputAISettings().shortcut) }
                Button("清除") { set(nil) }
            }
            if recording {
                ShortcutRecorder(voiceOnly: false, onRecord: { set($0) }, onCancel: { recording = false })
                    .frame(height: 1)
                Text("按组合键完成录制，Esc 取消。")
            }
            if let notice { Text(notice).foregroundStyle(.secondary) }
            else if let shortcut = preferences.wrappedValue.shortcut,
                    Self.conflicts(shortcut, settings: settings.shortcuts) {
                Text("与已配置的全局快捷键冲突，请重新录制。").foregroundStyle(.secondary)
            }
            Text("仅在输入法组词时触发，每次按键切换一个动作；Esc 返回普通候选翻译。需要先在 AI 连接中配置服务与密钥。")
                .foregroundStyle(.secondary)
            Text("继续打字会作废旧结果；Esc 停止，Tab 仅接受当前结果。安全输入期间不请求 AI。快捷键与 Rime 或其他应用的冲突需在实际输入时验证。")
                .foregroundStyle(.secondary)
        }
        .onDisappear { recording = false }
    }

    private func set(_ shortcut: Shortcut?) {
        recording = false
        if let shortcut, Self.conflicts(shortcut, settings: settings.shortcuts) {
            notice = "与已配置的全局快捷键冲突，请重新录制。"; return
        }
        preferences.wrappedValue.shortcut = shortcut; notice = nil
    }
    static func conflicts(_ shortcut: Shortcut, settings: ShortcutSettings) -> Bool {
        (Array(settings.bindings.values) + [settings.showSettings].compactMap { $0 }).contains {
            $0.modifiers == shortcut.modifiers && $0.key?.lowercased() == shortcut.key?.lowercased()
        }
    }
    private func label(_ shortcut: Shortcut?) -> String {
        guard let shortcut else { return "录制快捷键" }
        var label = ""
        for (modifier, symbol): (Shortcut.Modifiers, String) in [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")] {
            if shortcut.modifiers.contains(modifier) { label += symbol }
        }
        return label + (shortcut.key == "tab" ? "Tab" : shortcut.key?.uppercased() ?? "")
    }
}
