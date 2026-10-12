import SwiftUI
import RoarkTCore
import RoarkTPlatform

/// Settings presentation only. Runtime ownership stays with the feature controllers.
enum SettingsFeature: String, CaseIterable, Identifiable {
    case voice, selectionToolbar, selectionShortcuts, screenshot, screenshotHistory, pinning, inputMethodAI, candidateTranslation
    var id: String { rawValue }
    var feature: FeatureSettings.Feature? { FeatureSettings.Feature(rawValue: rawValue) }
    var title: String {
        switch self {
        case .voice: "语音"; case .selectionToolbar: "划词工具栏"; case .selectionShortcuts: "划词快捷键"
        case .screenshot: "截图"; case .screenshotHistory: "截图历史"; case .pinning: "贴图"
        case .inputMethodAI: "输入法内 AI"; case .candidateTranslation: "候选翻译"
        }
    }
    var symbol: String {
        switch self {
        case .voice: "waveform"; case .selectionToolbar: "cursorarrow.rays"; case .selectionShortcuts: "command"
        case .screenshot: "viewfinder"; case .screenshotHistory: "clock.arrow.circlepath"; case .pinning: "pin"
        case .inputMethodAI: "sparkles"; case .candidateTranslation: "character.bubble"
        }
    }
    var destination: SettingsSection {
        switch self {
        case .voice: .voice
        case .selectionToolbar: .selection
        case .selectionShortcuts: .shortcuts
        case .screenshot, .screenshotHistory, .pinning: .screenshot
        case .inputMethodAI, .candidateTranslation: .input
        }
    }
    func isEnabled(in settings: AppSettings) -> Bool {
        feature.map { settings.enabledFeatures[$0] } ?? settings.input.candidateTranslation
    }
    func binding(in settings: Binding<AppSettings>) -> Binding<Bool> {
        Binding(get: { isEnabled(in: settings.wrappedValue) }, set: { value in
            if let feature { settings.wrappedValue.enabledFeatures[feature] = value }
            else { settings.wrappedValue.input.candidateTranslation = value }
        })
    }
    struct Status: Equatable {
        let text: String
        let attention: Bool
    }
    func status(settings: AppSettings, granted: Set<Permissions.Kind>, aiConfigured: Bool) -> Status {
        guard isEnabled(in: settings) else { return Status(text: "已关闭 · 设置仍会保留", attention: false) }
        if self == .voice && !granted.contains(.microphone) { return Status(text: "需要麦克风权限", attention: true) }
        if [.voice, .selectionToolbar, .selectionShortcuts].contains(self) && !granted.contains(.accessibility) {
            return Status(text: "需要辅助功能权限", attention: true)
        }
        if self == .screenshot && !granted.contains(.screenRecording) { return Status(text: "需要屏幕录制权限", attention: true) }
        let hint: String
        switch self {
        case .voice: hint = "按住 " + Self.shortcut(settings.shortcuts.bindings[.voiceHoldToTalk])
        case .selectionToolbar:
            if settings.selection.trigger == .shortcutOnly { return Status(text: "已启用 · 当前设为仅快捷键", attention: true) }
            hint = "选中文字后出现"
        case .selectionShortcuts: hint = Self.shortcut(settings.shortcuts.bindings[.translateSelection]) + " 翻译"
        case .screenshot: hint = Self.shortcut(settings.shortcuts.bindings[.screenshot]) + " 框选"
        case .screenshotHistory: hint = Self.shortcut(settings.shortcuts.bindings[.screenshotHistory]) + " 查看"
        case .pinning: hint = Self.shortcut(settings.shortcuts.bindings[.togglePins]) + " 隐藏 / 显示"
        case .inputMethodAI:
            if !aiConfigured { return Status(text: "需要配置 AI 连接", attention: true) }
            if settings.input.inputAI?.enabled != true { return Status(text: "需要在输入法页启用 AI 动作", attention: true) }
            hint = Self.shortcut((settings.input.inputAI ?? InputAISettings()).shortcut) + " 切换动作"
        case .candidateTranslation: hint = "Tab 填入译文"
        }
        return Status(text: "已启用 · " + hint, attention: false)
    }
    static func shortcut(_ value: Shortcut?) -> String {
        guard let value else { return "未设快捷键" }
        let symbols: [(Shortcut.Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"), (.function, "Fn")]
        return symbols.filter { value.modifiers.contains($0.0) }.map(\.1).joined() + (value.key == "tab" ? "Tab" : value.key?.uppercased() ?? "")
    }
}

struct FeatureSettingsView: View {
    @Binding var settings: AppSettings
    let permissions: PermissionCenter
    let aiConfigured: Bool
    let navigate: (SettingsSection) -> Void
    @Environment(\.colorScheme) private var scheme
    private var granted: Set<Permissions.Kind> { Set(permissions.items.filter { $0.status == .granted }.map(\.kind)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("日常工具", [.voice, .selectionToolbar, .selectionShortcuts, .screenshot])
            group("截图与整理", [.screenshotHistory, .pinning])
            group("输入增强", [.inputMethodAI, .candidateTranslation])
            Text("中文输入始终可用。关闭功能会保留偏好，重新开启无需重设。")
                .font(.system(size: 12)).foregroundStyle(Tokens.palette(scheme).secondary)
        }
    }
    private func group(_ title: String, _ items: [SettingsFeature]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DesignSectionTitle(title: title)
            DesignCard {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        let status = item.status(settings: settings, granted: granted, aiConfigured: aiConfigured)
                        SettingsControlRow(item.title, detail: status.text, symbol: item.symbol,
                            status: !item.isEnabled(in: settings) ? .off : status.attention ? .attention : .on) {
                            Button { navigate(item.destination) } label: {
                                HStack(spacing: 4) { Text("设置"); Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)) }
                            }.buttonStyle(DesignButtonStyle(variant: .ghost))
                                .accessibilityLabel(item.title + "设置")
                            SettingsToggle(title: item.title, isOn: item.binding(in: $settings))
                                .accessibilityIdentifier("feature-" + item.rawValue)
                        }
                        if item != items.last { DesignRule() }
                    }
                }
            }
        }
    }
}

struct SettingsFeatureNotices: View {
    let items: [SettingsFeature]
    @Binding var settings: AppSettings
    private var disabledItems: [SettingsFeature] { items.filter { !$0.isEnabled(in: settings) } }
    var body: some View {
        if !disabledItems.isEmpty {
            DesignCard {
                VStack(spacing: 0) {
                    ForEach(disabledItems) { item in
                        SettingsControlRow(item.title, detail: "此功能已关闭", symbol: item.symbol, status: .off) {
                            Button("开启") { item.binding(in: $settings).wrappedValue = true }
                                .accessibilityLabel("开启" + item.title)
                        }
                        if item != disabledItems.last { DesignRule() }
                    }
                }
            }
        }
    }
}

struct SettingsFeatureNotice: View {
    let item: SettingsFeature
    @Binding var settings: AppSettings
    var body: some View { SettingsFeatureNotices(items: [item], settings: $settings) }
}

struct SettingsFeatureContent<Content: View>: View {
    let item: SettingsFeature
    @Binding var settings: AppSettings
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsFeatureNotice(item: item, settings: $settings)
            content().disabled(!item.isEnabled(in: settings)).opacity(item.isEnabled(in: settings) ? 1 : 0.48)
        }
    }
}
