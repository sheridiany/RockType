import Foundation
import RoarkTCore
@preconcurrency import Translation

typealias DynamicTranslationBackendError = CandidateTranslationFailure

@MainActor
protocol DynamicTextTranslating: AnyObject {
    func translate(_ text: String, direction: DynamicTranslationDirection) async throws -> String
}

@MainActor
final class UnavailableDynamicTranslator: DynamicTextTranslating {
    func translate(_ text: String, direction: DynamicTranslationDirection) async throws -> String {
        throw DynamicTranslationBackendError.requiresMacOS26
    }
}

// The substitutable boundary is Apple's session API, not coordinator internals.
@MainActor
protocol SystemTranslationSession: AnyObject {
    func translate(_ text: String) async throws -> String
}

@available(macOS 26.0, *)
@MainActor
private final class AppleTranslationSession: SystemTranslationSession {
    private let session: TranslationSession

    init(direction: DynamicTranslationDirection) {
        let chinese = Locale.Language(identifier: "zh-Hans")
        let english = Locale.Language(identifier: "en")
        session = direction == .chineseToEnglish
            ? TranslationSession(installedSource: chinese, target: english)
            : TranslationSession(installedSource: english, target: chinese)
    }

    func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }
}

@available(macOS 26.0, *)
@MainActor
final class AppleDynamicTranslator: DynamicTextTranslating {
    private let makeSession: (DynamicTranslationDirection) -> any SystemTranslationSession
    private var chineseToEnglish: (any SystemTranslationSession)?
    private var englishToChinese: (any SystemTranslationSession)?

    init(makeSession: @escaping (DynamicTranslationDirection) -> any SystemTranslationSession = {
        AppleTranslationSession(direction: $0)
    }) {
        self.makeSession = makeSession
    }

    func translate(_ text: String, direction: DynamicTranslationDirection) async throws -> String {
        do {
            return try await translatedText(for: text, direction: direction)
        } catch {
            let failure = Self.normalized(error)
            // Only Apple's explicit internal/session failure gets one automatic
            // retry. Delay first so cancelled/superseded work cannot reset a
            // newer session. User-initiated retries are a separate action.
            guard TranslationError.internalError ~= error, !(failure is CancellationError) else { throw failure }
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            resetSession(for: direction)
            do {
                return try await translatedText(for: text, direction: direction)
            } catch {
                throw Self.normalized(error)
            }
        }
    }

    private static func normalized(_ error: Error) -> Error {
        if Task.isCancelled || error is CancellationError || TranslationError.alreadyCancelled ~= error {
            return CancellationError()
        }
        switch error {
        case TranslationError.notInstalled: return DynamicTranslationBackendError.languagePackMissing
        case TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage,
             TranslationError.unsupportedLanguagePairing: return DynamicTranslationBackendError.unsupportedLanguage
        case TranslationError.nothingToTranslate, TranslationError.unableToIdentifyLanguage:
            return DynamicTranslationBackendError.invalidRequest
        default: return CandidateTranslationFailure.from(error)
        }
    }

    private func translatedText(for text: String, direction: DynamicTranslationDirection) async throws -> String {
        try Task.checkCancellation()
        let text = try await session(for: direction).translate(text)
        try Task.checkCancellation()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetSession(for direction: DynamicTranslationDirection) {
        switch direction {
        case .chineseToEnglish: chineseToEnglish = nil
        case .englishToChinese: englishToChinese = nil
        }
    }

    private func session(for direction: DynamicTranslationDirection) -> any SystemTranslationSession {
        switch direction {
        case .chineseToEnglish:
            if let chineseToEnglish { return chineseToEnglish }
            let session = makeSession(direction)
            chineseToEnglish = session
            return session
        case .englishToChinese:
            if let englishToChinese { return englishToChinese }
            let session = makeSession(direction)
            englishToChinese = session
            return session
        }
    }
}

@MainActor
enum DynamicTranslatorFactory {
    static func make() -> any DynamicTextTranslating {
        if #available(macOS 26.0, *) { return AppleDynamicTranslator() }
        return UnavailableDynamicTranslator()
    }
}
