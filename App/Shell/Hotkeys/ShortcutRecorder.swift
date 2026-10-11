import AppKit
import SwiftUI
import RoarkTCore
import RoarkTPlatform

/// A first-responder field consumes only events while explicitly recording.
/// Escape cancels, including when leaving the pane or resigning the window.
struct ShortcutRecorder: NSViewRepresentable {
    let voiceOnly: Bool
    let onRecord: (Shortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.voiceOnly = voiceOnly; view.onRecord = onRecord; view.onCancel = onCancel
        return view
    }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.voiceOnly = voiceOnly; view.onRecord = onRecord; view.onCancel = onCancel
    }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.finish(nil) }

    final class CaptureView: NSView {
        var voiceOnly = false
        var onRecord: ((Shortcut) -> Void)?
        var onCancel: (() -> Void)?
        private var finished = false
        private var sawFn = false
        private var observer: NSObjectProtocol?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.makeFirstResponder(self)
            setAccessibilityLabel("录制快捷键，按 Escape 取消")
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                               object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(nil) }
            }
        }
        override func resignFirstResponder() -> Bool { finish(nil); return true }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { keyDown(with: event); return true }
        override func keyDown(with event: NSEvent) {
            guard !finished else { return }
            if event.keyCode == 53 { finish(nil); return }
            sawFn = false
            guard !voiceOnly, !event.isARepeat, !event.modifierFlags.contains(.function),
                  let key = GlobalHotkeys.key(forPhysicalCode: event.keyCode) else { NSSound.beep(); return }
            var modifiers: Shortcut.Modifiers = []
            if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
            if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
            if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
            if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
            guard !modifiers.intersection([.control, .option, .command]).isEmpty else { NSSound.beep(); return }
            finish(Shortcut(key: key, modifiers: modifiers))
        }
        override func flagsChanged(with event: NSEvent) {
            guard voiceOnly else { return }
            let other = event.modifierFlags.intersection([.control, .option, .command, .shift])
            if !other.isEmpty { sawFn = false; return }
            if event.keyCode == 63, event.modifierFlags.contains(.function) { sawFn = true }
            else if sawFn, !event.modifierFlags.contains(.function) { finish(Shortcut(key: nil, modifiers: .function)) }
        }
        func finish(_ shortcut: Shortcut?) {
            guard !finished else { return }
            finished = true
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            // Leave AppKit responder callbacks before removing this view or registering keys.
            let record = onRecord, cancel = onCancel
            Task { @MainActor in
                if let shortcut { record?(shortcut) } else { cancel?() }
            }
        }
        isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

struct HotkeySettingsView: View {
    @Bindable var center: HotkeyCenter
    var body: some View {
        Form {
            Section("全局快捷键") {
                ForEach(HotkeyCenter.Action.allCases) { action in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(action.title)
                            Spacer()
                            Button(center.recording == action ? "按下组合键…" : label(center.shortcut(for: action))) {
                                center.beginRecording(action)
                            }
                            Button("恢复默认") { center.restoreDefault(for: action) }
                            Button("清除") { center.set(nil, for: action) }
                        }
                        Text(center.statuses[action]?.text ?? "未注册").foregroundStyle(.secondary)
                        if center.recording == action {
                            Text(action == .voiceHoldToTalk ? "按下并松开 Fn；Esc 取消。" : "按组合键完成录制；Esc 取消。")
                            ShortcutRecorder(voiceOnly: action == .voiceHoldToTalk,
                                onRecord: { center.set($0, for: action) }, onCancel: {
                                    if center.recording == action { center.cancelRecording() }
                                })
                                .frame(height: 1)
                        }
                    }
                }
                Button("重试注册") { center.retry() }
            }
            Section {
                Text("截图、翻译与总结使用上方快捷键；语音按住 Fn 录音，松开后识别。")
                Text("Fn 由系统共同监听；如同时触发系统听写或输入源切换，请在键盘设置中调整 Fn 行为。")
                Text("输入法内 AI 快捷键即将推出。")
                if let notice = center.notice { Text(notice) }
            }
        }
        .formStyle(.grouped)
        .onDisappear { if center.recording != nil { center.cancelRecording() } }
    }

    private func label(_ shortcut: Shortcut?) -> String {
        guard let shortcut else { return "录制快捷键" }
        var text = ""
        for (modifier, symbol): (Shortcut.Modifiers, String) in [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"), (.function, "Fn")] {
            if shortcut.modifiers.contains(modifier) { text += symbol }
        }
        return text + (shortcut.key?.uppercased() ?? "")
    }
}
