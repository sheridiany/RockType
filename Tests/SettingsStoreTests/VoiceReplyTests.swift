import Foundation
import Testing
@testable import RoarkTApp

@Test @MainActor func voiceReplyFirstTerminalEventWins() async throws {
    let gate = VoiceReply<Int>()
    let result = try await gate.wait(seconds: 1) {
        $0.finish(.success(42))
        $0.finish(.failure(VoiceFailure.unavailable))
        $0.finish(.success(99))
    }
    #expect(result == 42)
    gate.finish(.failure(VoiceFailure.timeout)) // A delayed transport failure cannot resume twice.
}

@Test @MainActor func voiceReplyTimeoutIgnoresLateTransportSuccess() async {
    let gate = VoiceReply<Int>()
    do {
        _ = try await gate.wait(seconds: 0) { _ in }
        Issue.record("A silent transport must time out")
    } catch {
        #expect((error as? VoiceFailure) == .timeout)
    }
    gate.finish(.success(42))
}

@Test @MainActor func voiceReplyCancellationBeforeSendDoesNotStartTransport() async {
    var sent = false
    let gate = VoiceReply<Int>()
    let task = Task { @MainActor in
        try await gate.wait(seconds: 1) { _ in sent = true }
    }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Pre-cancelled calls must fail")
    } catch { #expect(error is CancellationError) }
    #expect(!sent)
}

@Test @MainActor func voiceReplyCancellationWhileWaitingSettlesOnce() async {
    let (started, signal) = AsyncStream<Void>.makeStream()
    let gate = VoiceReply<Int>()
    let task = Task { @MainActor in
        try await gate.wait(seconds: 30) { _ in signal.yield(()); signal.finish() }
    }
    for await _ in started { break }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("In-flight cancellation must release the awaiting task")
    } catch { #expect(error is CancellationError) }
    gate.finish(.success(42))
}
