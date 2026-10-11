import AppKit
import SwiftUI
import Observation
import RoarkTPlatform

@MainActor @Observable final class VoiceHUDState {
    enum Phase { case hidden, preparing, recording, recognizing, done, failed }
    var phase: Phase = .hidden
    var message = ""
    var result = ""
    var levels = Array(repeating: 0.05, count: 9)
    var seconds = 0
}

@MainActor final class VoiceHUDController {
    let state: VoiceHUDState
    var onCancel: () -> Void = {}
    private var panel: NSPanel?
    init(state: VoiceHUDState) { self.state = state }
    func show() {
        if panel == nil {
            let panel = VoicePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
            panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: LiveVoiceHUD(state: state, cancel: { [weak self] in self?.onCancel() }))
            self.panel = panel
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrame(NSRect(x: frame.midX - 190, y: frame.minY + 36, width: 380, height: 180), display: true)
        panel.orderFrontRegardless()
    }
    func hide() { panel?.orderOut(nil) }
}
private final class VoicePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private struct LiveVoiceHUD: View {
    let state: VoiceHUDState
    let cancel: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack {
                Image(systemName: state.phase == .recording ? "mic.fill" : "waveform")
                    .foregroundStyle(state.phase == .recording ? palette.danger : palette.accent)
                Text(state.message).font(Tokens.Typography.font(Tokens.Typography.meta))
                Spacer()
                Button(action: cancel) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("取消或关闭语音")
            }
            if state.phase == .recording {
                HStack(alignment: .center, spacing: Tokens.Space.xs) {
                    ForEach(Array(state.levels.enumerated()), id: \.offset) { _, level in
                        Capsule().fill(palette.foreground).frame(width: 4, height: max(3, level * 26))
                    }
                    Text("\(state.seconds) 秒 · 松开 Fn 识别").font(Tokens.Typography.font(Tokens.Typography.caption))
                }.frame(height: 28).accessibilityLabel("录音波形，已录制 \(state.seconds) 秒")
            }
            if !state.result.isEmpty {
                Text(state.result).font(Tokens.Typography.font(Tokens.Typography.meta)).lineLimit(3)
                Button("复制识别结果") {
                    guard SecureInput.status() == .allowed else { return }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(state.result, forType: .string)
                }.buttonStyle(DesignButtonStyle())
            }
        }.padding(Tokens.Space.md).frame(width: 350, alignment: .leading)
            .foregroundStyle(palette.foreground).modifier(DesignSurface())
    }
}
