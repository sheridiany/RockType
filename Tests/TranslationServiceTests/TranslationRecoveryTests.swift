import Foundation
import RoarkTCore
import Testing
import Translation
@testable import RoarkTTranslationService

@MainActor
private final class ScriptedSystemSession: SystemTranslationSession {
    var outcomes: [Result<String, Error>]
    var onRequest: (() -> Void)?
    init(_ outcomes: [Result<String, Error>]) { self.outcomes = outcomes }
    func translate(_ text: String) async throws -> String {
        onRequest?()
        guard !outcomes.isEmpty else { return "unexpected extra attempt" }
        return try outcomes.removeFirst().get()
    }
}

@MainActor
private final class SuspendedSystemSession: SystemTranslationSession {
    let started: AsyncStream<Void>.Continuation
    var pending: CheckedContinuation<String, Error>?
    init(started: AsyncStream<Void>.Continuation) { self.started = started }
    func translate(_ text: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            started.yield(())
        }
    }
}

@Test @MainActor
func cancellationWhileSystemIsSuspendedWinsOverLatePackError() async {
    guard #available(macOS 26.0, *) else { return }
    let (events, started) = AsyncStream<Void>.makeStream()
    let api = SuspendedSystemSession(started: started)
    let translator = AppleDynamicTranslator(makeSession: { _ in api })
    let task = Task { try await translator.translate("你好", direction: .chineseToEnglish) }
    for await _ in events { break }
    task.cancel()
    api.pending?.resume(throwing: TranslationError.notInstalled)
    api.pending = nil
    do { _ = try await task.value; Issue.record("cancelled request returned a result") }
    catch { #expect(error is CancellationError) }
}

@Test @MainActor
func cancellationDuringBackoffPreventsAutomaticRetry() async throws {
    guard #available(macOS 26.0, *) else { return }
    let (events, started) = AsyncStream<Void>.makeStream()
    let api = ScriptedSystemSession([.failure(TranslationError.internalError), .success("next user request")])
    api.onRequest = { started.yield(()) }
    let translator = AppleDynamicTranslator(makeSession: { _ in api })
    let task = Task { try await translator.translate("你好", direction: .chineseToEnglish) }
    for await _ in events { break }
    task.cancel()
    do { _ = try await task.value; Issue.record("backoff cancellation was ignored") }
    catch { #expect(error is CancellationError) }
    #expect(try await translator.translate("你好", direction: .chineseToEnglish) == "next user request")
}

@Test(arguments: [("pack", 10), ("internal", 12), ("cancel", 4), ("unsupported", 14)]) @MainActor
func systemFailureMeaningSurvivesRequestReply(_ scenario: String, _ expectedCode: Int) async {
    guard #available(macOS 26.0, *) else { return }
    let error: Error
    switch scenario {
    case "pack": error = TranslationError.notInstalled
    case "internal": error = TranslationError.internalError
    case "cancel": error = TranslationError.alreadyCancelled
    default: error = TranslationError.unsupportedLanguagePairing
    }
    let api = ScriptedSystemSession([.failure(error), .failure(error)])
    let service = TranslationXPCService(
        coordinator: TranslationCoordinator(backend: AppleDynamicTranslator(makeSession: { _ in api })),
        role: .inputMethod
    )
    let response = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: UUID().uuidString, generation: 1,
            request: ["version": "2", "rawInput": "nihao", "sourceText": "你好",
                      "identity": "0:5:0", "scope": "whole", "direction": "zh-en"]) { _, _, _, text, error in
            continuation.resume(returning: (text, error as NSError?))
        }
    }
    #expect(response.0 == nil)
    #expect(response.1?.domain == Identifiers.translationServiceName)
    #expect(response.1?.code == expectedCode)
    if let error = response.1 {
        #expect(CandidateTranslationFailure.from(error).canRetry == (scenario == "internal"))
    }
}

@Test @MainActor
func transientSystemFailureRecoversOnce() async throws {
    guard #available(macOS 26.0, *) else { return }
    let api = ScriptedSystemSession([.failure(TranslationError.internalError), .success("Hello")])
    let translator = AppleDynamicTranslator(makeSession: { _ in api })
    #expect(try await translator.translate("你好", direction: .chineseToEnglish) == "Hello")
}

@Test @MainActor
func persistentInternalFailureDoesNotRetryForeverOrReportMissingPack() async {
    guard #available(macOS 26.0, *) else { return }
    let api = ScriptedSystemSession([.failure(TranslationError.internalError),
                                    .failure(TranslationError.internalError), .success("unexpected third attempt")])
    let translator = AppleDynamicTranslator(makeSession: { _ in api })
    do {
        _ = try await translator.translate("你好", direction: .chineseToEnglish)
        Issue.record("only one automatic retry is allowed")
    } catch {
        #expect(error as? CandidateTranslationFailure == .serviceUnavailable)
    }
}

@Test @MainActor
func unknownSystemFailureDoesNotRetryOrReportMissingPack() async {
    guard #available(macOS 26.0, *) else { return }
    let api = ScriptedSystemSession([.failure(NSError(domain: "SystemFixture", code: 81)), .success("unexpected retry")])
    let translator = AppleDynamicTranslator(makeSession: { _ in api })
    do {
        _ = try await translator.translate("你好", direction: .chineseToEnglish)
        Issue.record("unknown failures must not be automatically retried")
    } catch {
        #expect(error as? CandidateTranslationFailure == .serviceUnavailable)
    }
}

@Test @MainActor
func alreadyCancelledTaskDoesNotConsumeSystemResult() async throws {
    guard #available(macOS 26.0, *) else { return }
    let api = ScriptedSystemSession([.success("first result")])
    let translator = AppleDynamicTranslator(makeSession: { _ in api })
    let task = Task { try await translator.translate("你好", direction: .chineseToEnglish) }
    task.cancel()
    do { _ = try await task.value; Issue.record("cancelled task returned text") }
    catch { #expect(error is CancellationError) }
    #expect(try await translator.translate("你好", direction: .chineseToEnglish) == "first result")
}

@Test @MainActor
func missingLanguagePackIsNotAutomaticallyRetried() async {
    guard #available(macOS 26.0, *) else { return }
    let api = ScriptedSystemSession([.failure(TranslationError.notInstalled), .success("unexpected retry")])
    let translator = AppleDynamicTranslator(makeSession: { _ in api })
    do {
        _ = try await translator.translate("你好", direction: .chineseToEnglish)
        Issue.record("missing language pack must require setup, not retry")
    } catch {
        #expect(error as? CandidateTranslationFailure == .languagePackMissing)
    }
}

@Test @MainActor
func cancelledSystemTranslationDoesNotRetryOrBecomeMissingPack() async {
    guard #available(macOS 26.0, *) else { return }
    let api = ScriptedSystemSession([.failure(CancellationError()), .success("unexpected retry")])
    let translator = AppleDynamicTranslator(makeSession: { _ in api })
    do {
        _ = try await translator.translate("你好", direction: .chineseToEnglish)
        Issue.record("cancellation must not return a retried result")
    } catch {
        #expect(error is CancellationError)
    }
}
