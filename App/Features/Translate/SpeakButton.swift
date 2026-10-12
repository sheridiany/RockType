import AppKit
import Combine
import SwiftUI

struct SpeakButton: View {
    let speaker: TextSpeaker
    let text: String
    var language: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let active = speaker.isActive
        Button {
            if speaker.isActive { speaker.stop() } else { speaker.speak(text, language: language) }
        } label: {
            Image(systemName: active ? "stop.fill" : speaker.notice == nil ? "speaker.wave.2" : "speaker.slash")
                .font(Tokens.Typography.font(Tokens.Size.compactIcon, weight: .medium))
                .frame(width: Tokens.Size.compactIcon, height: Tokens.Size.compactIcon)
                .foregroundStyle(active ? Tokens.palette(scheme).accent : Tokens.palette(scheme).secondary)
        }
        .buttonStyle(DesignButtonStyle(variant: .ghost))
        .disabled(!active && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(active ? "停止朗读" : speaker.notice ?? "使用系统声音朗读")
        .accessibilityLabel(active ? "停止朗读" : "朗读文字")
        .accessibilityValue(speaker.state == .preparing ? "正在准备" : speaker.isSpeaking ? "正在朗读" : speaker.notice ?? "已停止")
        .background(SpeechWindowAttachment(speaker: speaker).frame(width: 0, height: 0).allowsHitTesting(false))
        .onChange(of: text) { _, _ in speaker.stop() }
        .onChange(of: language) { _, _ in speaker.stop() }
        .onDisappear { speaker.stop() }
    }
}

private struct SpeechWindowAttachment: NSViewRepresentable {
    let speaker: TextSpeaker
    func makeNSView(context: Context) -> SpeechWindowAnchor { SpeechWindowAnchor(speaker: speaker) }
    func updateNSView(_ view: SpeechWindowAnchor, context: Context) { view.attach(speaker) }
    static func dismantleNSView(_ view: SpeechWindowAnchor, coordinator: ()) { view.detach() }
}

/// A retained SwiftUI host may not disappear when its NSWindow closes. Observe the actual owning
/// window as well; never observe unrelated windows or stop another speaker's current playback.
@MainActor final class SpeechWindowAnchor: NSView {
    private weak var speaker: TextSpeaker?
    private weak var observedWindow: NSWindow?
    private var closeObservation: AnyCancellable?

    init(speaker: TextSpeaker) {
        self.speaker = speaker
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(_ next: TextSpeaker) {
        guard speaker !== next else { return }
        speaker?.stop(); speaker = next
    }
    func detach() {
        closeObservation = nil; observedWindow = nil
        speaker?.stop(); speaker = nil
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard observedWindow !== window else { return }
        if observedWindow != nil { speaker?.stop() }
        closeObservation = nil; observedWindow = window
        if let window {
            closeObservation = NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
                .sink { [weak self] _ in
                    // NSWindow lifecycle notifications are delivered synchronously on AppKit's main thread.
                    MainActor.assumeIsolated { self?.speaker?.stop() }
                }
        }
    }
}
