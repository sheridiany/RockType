import Foundation
@preconcurrency import Translation

/// Only the identical installed-session API adapter is shared. Callers retain language
/// detection, availability checks, session lifetime, retry and error-mapping policies.
@available(macOS 26.0, *)
@MainActor
final class AppleTranslationSession: SystemTranslationSession {
    private let session: TranslationSession
    init(source: Locale.Language, target: Locale.Language) {
        session = TranslationSession(installedSource: source, target: target)
    }
    func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }
}
