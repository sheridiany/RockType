import SwiftUI
import RoarkTCore

struct InputAISettingsSection: View {
    @Binding var settings: AppSettings
    @State private var recording = false
    @State private var notice: String?
    private var preferences: Binding<InputAISettings> {
        Binding(get: { settings.input.inputAI ?? InputAISettings() }, set: { settings.input.inputAI = $0 })
    }
    var body: some View {
        Section("输入法内 AI") {
            Toggle("启用输入法内 AI", isOn: preferences.enabled)
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
            Text("仅在输入法组词时触发，每次按键切换一个动作；Esc 返回普通候选翻译。需要先在 AI 连接中配置服务与密钥。")
                .foregroundStyle(.secondary)
            Text("此键由输入法处理。与 Rime 或其他应用的冲突需在实际输入时验证。")
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
