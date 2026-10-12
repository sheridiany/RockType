import Foundation
import NaturalLanguage
import Observation
import RoarkTPlatform

struct SystemSpeechVoice: Equatable, Sendable {
    let identifier: String
    let language: String
    var quality: Int = 0
}
enum SpeechPlaybackEvent: Sendable { case started, finished, cancelled }

@MainActor protocol SpeechDriving: AnyObject, Sendable {
    var voices: [SystemSpeechVoice] { get }
    var defaultLanguage: String { get }
    func speak(_ text: String, voice: SystemSpeechVoice, request: UUID,
               report: @escaping @MainActor @Sendable (UUID, SpeechPlaybackEvent) -> Void) -> Bool
    func stop()
}

@MainActor @Observable final class TextSpeaker {
    enum Failure: Equatable {
        case protectedInput, tooLong, unavailableVoice, unavailableEngine
        var message: String {
            switch self {
            case .protectedInput: "输入保护检查未通过，无法朗读。请检查安全输入状态和辅助功能权限后重试。"
            case .tooLong: "文字过长，请缩短内容后再朗读。"
            case .unavailableVoice: "未找到这种语言的系统声音，请在系统设置中添加声音后重试。"
            case .unavailableEngine: "系统朗读未能开始，请稍后重试。"
            }
        }
    }
    enum State: Equatable { case idle, preparing, speaking, failed(Failure) }
    private(set) var state: State = .idle
    var isActive: Bool { state == .preparing || state == .speaking }
    var isSpeaking: Bool { state == .speaking }
    var notice: String? { if case .failed(let failure) = state { failure.message } else { nil } }

    private static weak var active: TextSpeaker?
    @ObservationIgnored private let driver: any SpeechDriving
    @ObservationIgnored private let allowed: @MainActor @Sendable () -> Bool
    @ObservationIgnored private let now: @MainActor @Sendable () -> TimeInterval
    @ObservationIgnored private var request: UUID?
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var monitor: Task<Void, Never>?

    init(driver: (any SpeechDriving)? = nil,
         allowed: @escaping @MainActor @Sendable () -> Bool = { SecureInput.status() == .allowed },
         now: @escaping @MainActor @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.driver = driver ?? SystemSpeechDriver()
        self.allowed = allowed; self.now = now
    }

    func speak(_ text: String, language: String? = nil) {
        stop()
        guard allowed() else { state = .failed(.protectedInput); return }
        guard text.utf16.count <= 32_000 else { state = .failed(.tooLong); return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let language = Self.language(for: text, hint: language, fallback: driver.defaultLanguage)
        guard let voice = Self.voice(for: language, in: driver.voices) else { state = .failed(.unavailableVoice); return }
        Self.active?.stop()
        Self.active = self
        let token = UUID(); request = token; startedAt = now(); state = .preparing
        guard driver.speak(text, voice: voice, request: token, report: { [weak self] in self?.receive($0, event: $1) }) else {
            stop(); state = .failed(.unavailableEngine); return
        }
        monitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                self?.checkPlayback()
                if self?.isActive != true { return }
            }
        }
    }

    func stop() {
        request = nil
        monitor?.cancel(); monitor = nil
        driver.stop()
        if Self.active === self { Self.active = nil }
        state = .idle
    }

    func checkPlayback() {
        guard isActive else { return }
        if !allowed() { stop(); state = .failed(.protectedInput) }
        else if state == .preparing, now() - startedAt >= 10 { stop(); state = .failed(.unavailableEngine) }
    }

    private func receive(_ token: UUID, event: SpeechPlaybackEvent) {
        guard request == token else { return }
        guard allowed() else { stop(); state = .failed(.protectedInput); return }
        switch event {
        case .started: state = .speaking
        case .finished, .cancelled: stop()
        }
    }

    deinit {
        monitor?.cancel()
        let driver = driver
        Task { @MainActor in driver.stop() }
    }

    nonisolated static func language(for text: String, hint: String?, fallback: String) -> String {
        if let hint, !hint.isEmpty, !["auto", "und"].contains(hint.lowercased()) {
            return hint.replacingOccurrences(of: "_", with: "-")
        }
        return NLLanguageRecognizer.dominantLanguage(for: String(text.prefix(2048)))?.rawValue ?? fallback
    }

    nonisolated static func voice(for language: String, in voices: [SystemSpeechVoice]) -> SystemSpeechVoice? {
        var tag = language.replacingOccurrences(of: "_", with: "-").lowercased()
        if tag == "zh-hans" { tag = "zh-cn" }
        if tag == "zh-hant" { tag = "zh-tw" }
        let primary = tag.split(separator: "-").first
        let candidates = voices.filter { $0.language.lowercased().split(separator: "-").first == primary }
        return candidates.sorted { lhs, rhs in
            let leftExact = lhs.language.lowercased() == tag, rightExact = rhs.language.lowercased() == tag
            if leftExact != rightExact { return leftExact }
            if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
            return lhs.identifier < rhs.identifier
        }.first
    }
}
