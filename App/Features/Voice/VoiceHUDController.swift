import AppKit
import Observation
import RoarkTPlatform

@MainActor @Observable final class VoiceHUDState {
    enum Phase { case hidden, preparing, loading, recording, recognizing, polishing, done, failed, noSpeech }
    var phase: Phase = .hidden
    var message = ""
    var result = ""
    var levels = Array(repeating: 0.05, count: 9) {
        didSet { onMeterChange?() }
    }
    @ObservationIgnored var onMeterChange: (() -> Void)?
}

/// Maps lifecycle states to the text-free capsule; only failures expose a card.
@MainActor final class VoiceHUDController {
    let state: VoiceHUDState
    var onCancel: () -> Void = {}
    private let hud: RoarkTVoiceHUD

    init(state: VoiceHUDState, hud: RoarkTVoiceHUD = RoarkTVoiceHUD(),
         canCopy: @escaping () -> Bool = { SecureInput.status() == .allowed },
         copy: @escaping (String) -> Void = {
             NSPasteboard.general.clearContents(); NSPasteboard.general.setString($0, forType: .string)
         }) {
        self.state = state
        self.hud = hud
        hud.onCancel = { [weak self] in self?.onCancel() }
        hud.onCopy = { [weak self] in
            guard let self, self.state.phase == .failed, canCopy() else { return }
            let text = self.state.result
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            copy(text)
        }
        state.onMeterChange = { [weak self] in
            guard let self, self.state.phase == .recording else { return }
            // The recorder supplies normalized amplitude; preserve the original drawing scale.
            let level = self.state.levels.last ?? 0
            self.hud.updateRecording(decibels: Float(level * 45 - 55))
        }
    }

    func show() {
        switch state.phase {
        case .hidden: hud.hide()
        case .preparing, .loading: hud.show(.preparing)
        case .recording: hud.show(.recording)
        case .recognizing: hud.show(.processing)
        case .polishing: hud.show(.polishing)
        case .noSpeech: hud.show(.noSpeech)
        case .done: hud.show(.success(state.message))
        case .failed:
            if state.result.isEmpty {
                hud.show(.notice(title: "语音未完成", detail: state.message))
            } else {
                hud.show(.result(state.result, reason: state.message))
            }
        }
    }
    func hide() { hud.hide() }
}
