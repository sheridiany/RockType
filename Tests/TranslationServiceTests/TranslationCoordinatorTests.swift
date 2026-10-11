import Foundation
import RoarkTCore
import Testing
@testable import RoarkTTranslationService

@MainActor
private final class FakeTranslator: DynamicTextTranslating {
    func translate(_ text: String, direction: DynamicTranslationDirection) async throws -> String {
        if text == "slow" {
            try await Task.sleep(for: .seconds(1))
        }
        return "translated:\(text)"
    }
}

private struct Reply: Sendable {
    let generation: Int64
    let translatedText: String?
    let errorCode: Int?
}

@Test @MainActor
func coordinatorRejectsOutOfOrderGenerationWithoutCancellingLatest() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let connectionID = UUID()
    let sessionID = UUID().uuidString
    let replies = AsyncStream<Reply> { continuation in
        let reply: @Sendable (Int64, String?, String?, String?, NSError?) -> Void = {
            generation, _, _, translatedText, error in
            continuation.yield(.init(
                generation: generation,
                translatedText: translatedText,
                errorCode: error?.code
            ))
        }
        coordinator.translate(
            connectionID: connectionID,
            sessionID: sessionID,
            generation: 2,
            request: candidate(raw: "hello", source: "hello"),
            withReply: reply
        )
        coordinator.translate(
            connectionID: connectionID,
            sessionID: sessionID,
            generation: 1,
            request: candidate(raw: "old", source: "old"),
            withReply: reply
        )
    }

    var received: [Reply] = []
    for await reply in replies {
        received.append(reply)
        if received.count == 2 { break }
    }

    #expect(received.contains { $0.generation == 1 && $0.errorCode == 2 })
    #expect(received.contains { $0.generation == 2 && $0.translatedText == "translated:hello" })
}

@Test @MainActor
func coordinatorCancellationRepliesAndReleasesTask() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let connectionID = UUID()
    let sessionID = UUID().uuidString
    let reply = await withCheckedContinuation { continuation in
        coordinator.translate(
            connectionID: connectionID,
            sessionID: sessionID,
            generation: 1,
            request: candidate(raw: "slow", source: "slow")
        ) { generation, _, _, _, error in
            continuation.resume(returning: Reply(
                generation: generation,
                translatedText: nil,
                errorCode: error?.code
            ))
        }
        coordinator.cancel(connectionID: connectionID, sessionID: sessionID, throughGeneration: 1)
    }
    #expect(reply.generation == 1)
    #expect(reply.errorCode == 4)
}

@Test @MainActor
func selectedChineseCandidateIsNotOverriddenByEnglishLookingPinyin() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let response = await withCheckedContinuation { continuation in
        coordinator.translate(
            connectionID: UUID(),
            sessionID: UUID().uuidString,
            generation: 1,
            request: candidate(raw: "can", source: "餐")
        ) { _, direction, source, text, error in
            continuation.resume(returning: (direction, source, text, error?.code))
        }
    }
    #expect(response.0 == "zh-en")
    #expect(response.1 == "餐")
    #expect(response.2 == "translated:餐")
    #expect(response.3 == nil)
}

@Test(arguments: ["hello", "café", "cafe\u{301}", "don’t"]) @MainActor
func selectedEnglishCompletionIsTranslatedInsteadOfItsInputCode(_ selected: String) async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let response = await withCheckedContinuation { continuation in
        coordinator.translate(
            connectionID: UUID(),
            sessionID: UUID().uuidString,
            generation: 1,
            request: candidate(raw: "hel", source: selected)
        ) { _, direction, source, text, error in
            continuation.resume(returning: (direction, source, text, error?.code))
        }
    }
    #expect(response.0 == "en-zh")
    #expect(response.1 == selected)
    #expect(response.2 == "translated:\(selected)")
    #expect(response.3 == nil)
}

@Test(arguments: [("café", "en-zh"), ("OpenAI你好", "zh-en"), ("𠀀", "zh-en")]) @MainActor
func versionedCandidateRequestUsesExplicitSource(_ selected: String, _ requestedDirection: String) async {
    let service = TranslationXPCService(coordinator: TranslationCoordinator(backend: FakeTranslator()), role: .inputMethod)
    let response = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: UUID().uuidString, generation: 1,
            request: ["version": "2", "rawInput": "cafe", "sourceText": selected,
                      "identity": "0:4:0", "scope": "whole", "direction": requestedDirection]) { _, direction, source, text, error in
            continuation.resume(returning: (direction, source, text, (error as NSError?)?.code))
        }
    }
    #expect(response.0 == requestedDirection)
    #expect(response.1 == selected)
    #expect(response.2 == "translated:\(selected)")
    #expect(response.3 == nil)
}

@Test(arguments: [("version", "99", 6), ("direction", "zh-en", 1), ("scope", "unknown", 1),
                  ("identity", "0:99:0", 1), ("rawInput", "", 1), ("extra", "ignored?", 1),
                  ("sourceText", "привет", 1)]) @MainActor
func invalidCandidateRequestDoesNotConsumeGeneration(_ key: String, _ value: String, _ expectedCode: Int) async {
    let service = TranslationXPCService(coordinator: TranslationCoordinator(backend: FakeTranslator()), role: .inputMethod)
    let sessionID = UUID().uuidString
    let valid = ["version": "2", "rawInput": "cafe", "sourceText": "café",
                 "identity": "0:4:0", "scope": "segment", "direction": "en-zh"]
    var invalid = valid
    invalid[key] = value
    let rejected = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: sessionID, generation: 1, request: invalid) { _, _, _, text, error in
            continuation.resume(returning: (text, (error as NSError?)?.code))
        }
    }
    #expect(rejected.0 == nil)
    #expect(rejected.1 == expectedCode)
    let accepted = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: sessionID, generation: 1, request: valid) { _, _, _, text, error in
            continuation.resume(returning: (text, (error as NSError?)?.code))
        }
    }
    #expect(accepted.0 == "translated:café")
    #expect(accepted.1 == nil)
}

@Test @MainActor
func mainAppRoleCannotSubmitVersionedTranslation() async {
    let service = TranslationXPCService(coordinator: TranslationCoordinator(backend: FakeTranslator()), role: .mainApp)
    let code = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: UUID().uuidString, generation: 1, request: [:]) { _, _, _, _, error in
            continuation.resume(returning: (error as NSError?)?.code)
        }
    }
    #expect(code == 5)
}

@Test @MainActor
func coordinatorTracksFreshControllerInput() {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    #expect(coordinator.currentControllerInputGeneration() == 0)
    coordinator.recordControllerInput()
    #expect(coordinator.currentControllerInputGeneration() == 1)
}

@Test @MainActor
func coordinatorRejectsNonUUIDSession() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let reply = await withCheckedContinuation { continuation in
        coordinator.translate(
            connectionID: UUID(),
            sessionID: "1",
            generation: 1,
            request: candidate(raw: "hello", source: "hello")
        ) { generation, _, _, _, error in
            continuation.resume(returning: Reply(
                generation: generation,
                translatedText: nil,
                errorCode: error?.code
            ))
        }
    }
    #expect(reply.generation == 1)
    #expect(reply.errorCode == 1)
}

private func candidate(raw: String, source: String) -> CandidateTranslationRequest {
    try! CandidateTranslationRequest(rawInput: raw, sourceText: source,
        identity: "0:\(raw.utf8.count):0", scope: .whole)
}

@Test @MainActor func cancellationBeforeRequestRejectsLateGeneration() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let connection = UUID()
    let session = UUID().uuidString
    coordinator.cancel(connectionID: connection, sessionID: session, throughGeneration: 2)
    let response = await withCheckedContinuation { continuation in
        coordinator.translate(connectionID: connection, sessionID: session, generation: 2,
                              request: candidate(raw: "hello", source: "hello")) { _, _, _, text, error in
            continuation.resume(returning: (text, error?.code))
        }
    }
    #expect(response.0 == nil)
    #expect(response.1 == 2)
}

@Test @MainActor func connectionsWithSameSessionDoNotCancelEachOther() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let first = UUID()
    let second = UUID()
    let session = UUID().uuidString
    coordinator.cancel(connectionID: first, sessionID: session, throughGeneration: 99)
    let response = await withCheckedContinuation { continuation in
        coordinator.translate(connectionID: second, sessionID: session, generation: 1,
                              request: candidate(raw: "hello", source: "hello")) { _, _, _, text, error in
            continuation.resume(returning: (text, error?.code))
        }
    }
    #expect(response.0 == "translated:hello")
    #expect(response.1 == nil)
}

@Test @MainActor func mainAppCannotCancelInputMethodRequest() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let app = TranslationXPCService(coordinator: coordinator, role: .mainApp)
    let session = UUID().uuidString
    let response = await withCheckedContinuation { continuation in
        coordinator.translate(connectionID: app.connectionID, sessionID: session, generation: 1,
                              request: candidate(raw: "hello", source: "hello")) { _, _, _, text, error in
            continuation.resume(returning: (text, error?.code))
        }
        app.cancel(sessionID: session, throughGeneration: 1)
    }
    #expect(response.0 == "translated:hello")
    #expect(response.1 == nil)
}

@MainActor
private final class SuspendedTranslator: DynamicTextTranslating {
    let started: AsyncStream<Void>.Continuation
    var pending: CheckedContinuation<String, Never>?
    init(started: AsyncStream<Void>.Continuation) { self.started = started }
    func translate(_ text: String, direction: DynamicTranslationDirection) async throws -> String {
        if text != "slow" { return "new result" }
        return await withCheckedContinuation { continuation in
            pending = continuation
            started.yield(())
        }
    }
}

@Test @MainActor func supersededBackendResultCannotBecomeSuccessfulReply() async {
    let (events, started) = AsyncStream<Void>.makeStream()
    let backend = SuspendedTranslator(started: started)
    let coordinator = TranslationCoordinator(backend: backend)
    let connection = UUID()
    let session = UUID().uuidString
    let (replies, output) = AsyncStream<Reply>.makeStream()
    let reply: @Sendable (Int64, String?, String?, String?, NSError?) -> Void = { generation, _, _, text, error in
        output.yield(Reply(generation: generation, translatedText: text, errorCode: error?.code))
    }
    coordinator.translate(connectionID: connection, sessionID: session, generation: 1,
                          request: candidate(raw: "slow", source: "slow"), withReply: reply)
    for await _ in events { break }
    coordinator.translate(connectionID: connection, sessionID: session, generation: 2,
                          request: candidate(raw: "new", source: "new"), withReply: reply)
    // Simulate a backend that ignores cancellation and returns its old result.
    backend.pending?.resume(returning: "obsolete result")
    backend.pending = nil
    var received: [Reply] = []
    for await response in replies {
        received.append(response)
        if received.count == 2 { break }
    }
    #expect(received.contains { $0.generation == 1 && $0.translatedText == nil && $0.errorCode == 4 })
    #expect(received.contains { $0.generation == 2 && $0.translatedText == "new result" && $0.errorCode == nil })
}

@Test(arguments: [Int64(0), -1]) @MainActor func nonPositiveGenerationIsRejected(_ generation: Int64) async {
    let service = TranslationXPCService(coordinator: TranslationCoordinator(backend: FakeTranslator()), role: .inputMethod)
    let code = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: UUID().uuidString, generation: generation,
            request: candidate(raw: "hello", source: "hello").payload) { _, _, _, _, error in
            continuation.resume(returning: (error as NSError?)?.code)
        }
    }
    #expect(code == 1)
}
