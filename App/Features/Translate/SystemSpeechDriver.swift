import AVFoundation
import Foundation

@MainActor final class SystemSpeechDriver: SpeechDriving {
    private var synthesizer: AVSpeechSynthesizer?
    private var bridge: SpeechDelegateBridge?

    var defaultLanguage: String { AVSpeechSynthesisVoice.currentLanguageCode() }
    var voices: [SystemSpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            // Use Apple system voices only, never personal/novelty or third-party voice extensions.
            $0.identifier.hasPrefix("com.apple.") && !$0.voiceTraits.contains(.isPersonalVoice) && !$0.voiceTraits.contains(.isNoveltyVoice)
        }.map { .init(identifier: $0.identifier, language: $0.language, quality: $0.quality.rawValue) }
    }

    func speak(_ text: String, voice: SystemSpeechVoice, request: UUID,
               report: @escaping @MainActor @Sendable (UUID, SpeechPlaybackEvent) -> Void) -> Bool {
        stop()
        guard let nativeVoice = AVSpeechSynthesisVoice(identifier: voice.identifier) else { return false }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = nativeVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        let bridge = SpeechDelegateBridge(utterance: ObjectIdentifier(utterance), request: request, report: report)
        let synthesizer = AVSpeechSynthesizer()
        self.synthesizer = synthesizer; self.bridge = bridge
        synthesizer.delegate = bridge
        synthesizer.speak(utterance)
        return true
    }

    func stop() {
        synthesizer?.delegate = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil; bridge = nil
    }
}

/// Delegate callbacks can arrive on another executor. Only immutable IDs/events cross to MainActor;
/// neither the non-Sendable synthesizer nor the utterance is captured by a task.
private final class SpeechDelegateBridge: NSObject, AVSpeechSynthesizerDelegate {
    private let utterance: ObjectIdentifier
    private let request: UUID
    private let report: @MainActor @Sendable (UUID, SpeechPlaybackEvent) -> Void
    init(utterance: ObjectIdentifier, request: UUID,
         report: @escaping @MainActor @Sendable (UUID, SpeechPlaybackEvent) -> Void) {
        self.utterance = utterance; self.request = request; self.report = report
    }
    private func send(_ event: SpeechPlaybackEvent, for utterance: AVSpeechUtterance) {
        guard ObjectIdentifier(utterance) == self.utterance else { return }
        let request = request, report = report
        Task { @MainActor in report(request, event) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        send(.started, for: utterance)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        send(.finished, for: utterance)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        send(.cancelled, for: utterance)
    }
}
