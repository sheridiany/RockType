import SwiftUI
import Carbon

/// Only explicit actions request access. Reading status never opens system dialogs.
struct PermissionCenterView: View {
    @Bindable var center: PermissionCenter
    @State private var input = InputSourceManager()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignSectionTitle(title: "系统权限 · 按需开启")
            ForEach(center.items) { item in
                DesignCard {
                    HStack {
                        Text(item.title).fontWeight(.medium)
                        Spacer()
                        Chip(text: item.statusText, tone: item.status == .granted ? .ok : .neutral)
                    }
                    Text(item.purpose).font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(Tokens.palette(scheme).secondary)
                    if item.status != .granted {
                        HStack {
                            Button(center.requesting == item.kind ? "正在请求…" : "授权\(item.title)") {
                                Task { await center.request(item.kind) }
                            }
                            .disabled(center.requesting != nil || item.status == .restricted)
                            .buttonStyle(DesignButtonStyle())
                            Button("打开系统设置") { center.openSettings(item.kind) }
                                .buttonStyle(DesignButtonStyle(variant: .ghost))
                        }
                    }
                }
            }
            if let message = center.message { Notice(text: message, tone: .warn) }
            Text("普通打字无需这些权限。授权或撤销后会自动更新状态；截图需重新触发。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(Tokens.palette(scheme).secondary)
            DesignSectionTitle(title: "输入法启用与检查")
            InputSourceSettingsView(input: input)
        }.onAppear { center.refresh() }
    }
}

struct InputSourceSettingsView: View {
    let input: InputSourceManager
    @State private var trial = ""
    @State private var busy = false
    @State private var inputTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        DesignCard {
            HStack {
                Text("RockType 输入源").fontWeight(.medium)
                Spacer()
                Chip(text: input.snapshot.addedIDs.isEmpty ? "尚未添加" : "已添加",
                     tone: input.snapshot.addedIDs.isEmpty ? .neutral : .ok)
            }
            Text("系统设置 → 键盘 → 输入法 → 编辑 → ＋ → 简体中文，添加 RockType Pinyin 或 RockType Shuangpin。")
                .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(Tokens.palette(scheme).secondary)
            HStack {
                Button("打开键盘设置") { run { await input.openKeyboardSettings() } }
                    .buttonStyle(DesignButtonStyle()).disabled(busy)
                Button("刷新状态") { input.refresh() }.buttonStyle(DesignButtonStyle(variant: .ghost))
            }
            if let message = input.settingsMessage { Notice(text: message, tone: .warn) }
            DesignRule()
            Notice(text: input.message, tone: input.verified ? .ok : .neutral)
            if input.isVerifying {
                TextField("在这里试打 nihao 并选字", text: $trial)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("输入法试打")
                    .disabled(busy)
            }
            HStack {
                Button("开始试打验证") { trial = ""; run { await input.beginVerification() } }
                    .buttonStyle(DesignButtonStyle()).disabled(busy || input.snapshot.selectedRoarkTID == nil)
                if input.isVerifying {
                    Button("验证试打") { run { await input.verify() } }
                        .buttonStyle(DesignButtonStyle(variant: .primary)).disabled(busy)
                }
            }
            Text("验证只读取按键计数；试打文字不保存、不发送。")
                .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(Tokens.palette(scheme).secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in input.refresh() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))) { _ in input.refresh() }
        .onDisappear { inputTask?.cancel(); inputTask = nil; input.stop(); busy = false; trial = "" }
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        busy = true
        inputTask = Task { @MainActor in
            await action()
            if !Task.isCancelled { busy = false }
        }
    }
}
