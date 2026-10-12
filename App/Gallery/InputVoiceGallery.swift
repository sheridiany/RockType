#if DEBUG
import SwiftUI

@MainActor
enum InputVoiceGallery {
    static let entries: [GalleryEntry] = CandidatePresentation.State.allCases.map { state in
        GalleryEntry(surface: "candidate", state: state.rawValue, title: "候选窗 · " + state.title) {
            AnyView(CandidateDemo(initial: InputFixtures.candidate(state)).id(state.rawValue))
        }
    } + InputModePresentation.allCases.map { mode in
        GalleryEntry(surface: "input-mode", state: mode.rawValue, title: "输入模式 · " + mode.title) {
            AnyView(InputModeView(model: mode))
        }
    } + VoicePresentation.State.allCases.map { state in
        GalleryEntry(surface: "voice-hud", state: state.rawValue, title: "语音 HUD · " + state.title) {
            AnyView(VoiceHUDDemo(initial: state).id(state.rawValue))
        }
    }
}

#endif
