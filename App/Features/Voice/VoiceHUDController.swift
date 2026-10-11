import AppKit
import Observation
import RoarkTPlatform

@MainActor @Observable final class VoiceHUDState {
    enum Phase { case hidden, preparing, loading, recording, recognizing, polishing, done, failed }
    var phase: Phase = .hidden
    var message = ""
    var result = ""
    var levels = Array(repeating: 0.05, count: 9) {
        didSet { onMeterChange?() }
    }
    var seconds = 0
    @ObservationIgnored var onMeterChange: (() -> Void)?
}

/// Adapts the existing lifecycle to the original compact native presentation.
@MainActor final class VoiceHUDController {
    let state: VoiceHUDState
    var onCancel: () -> Void = {}
    private let hud: RoarkTVoiceHUD

    init(state: VoiceHUDState, hud: RoarkTVoiceHUD = RoarkTVoiceHUD()) {
        self.state = state
        self.hud = hud
        hud.onCancel = { [weak self] in self?.onCancel() }
        hud.onCopy = { [weak self] in
            guard let self, !state.result.isEmpty, SecureInput.status() == .allowed else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.result, forType: .string)
        }
        state.onMeterChange = { [weak self] in
            guard let self, state.phase == .recording else { return }
            // The recorder supplies normalized amplitude; preserve the original drawing scale.
            let level = state.levels.last ?? 0
            hud.updateRecording(elapsed: TimeInterval(state.seconds), decibels: Float(level * 45 - 55))
        }
    }

    func show() {
        switch state.phase {
        case .hidden: hud.hide()
        case .preparing, .loading: hud.show(.activity(state.message))
        case .recording: hud.show(.recording)
        case .recognizing, .polishing: hud.show(.activity(state.message))
        case .done: hud.show(.success(state.message))
        case .failed:
            if state.result.isEmpty {
                hud.show(.notice(title: "语音输入", detail: state.message))
            } else {
                hud.show(.result(state.result, reason: state.message))
            }
        }
    }
    func hide() { hud.hide() }
}
