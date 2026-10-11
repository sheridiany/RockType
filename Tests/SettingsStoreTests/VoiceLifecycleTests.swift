import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class RecordingDouble: VoiceRecording {
    var level: Double = 0.5
    var active = false
    var isRecording: Bool { active }
    var starts = 0
    func start() throws { starts += 1; active = true }
    func finish() -> Data { active = false; return Data(repeating: 0, count: 64) }
    func cancel() { active = false }
}
@MainActor private final class WorkerDouble: VoiceRecognizing {
    var stopped = 0
    var prepared = 0
    var pending: CheckedContinuation<String, any Error>?
    func prepare(directory: URL) async throws { prepared += 1 }
    func transcribe(_ audio: Data) async throws -> String {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func stop() { stopped += 1 }
    func resolve(_ text: String) { pending?.resume(returning: text); pending = nil }
}
@MainActor private final class BridgeDouble: VoiceCommitting {
    var texts: [String] = []
    var accept = true
    var delayed = false
    var pending: CheckedContinuation<VoiceTarget, any Error>?
    func capture(pid: Int32) async throws -> VoiceTarget {
        if delayed { return try await withCheckedThrowingContinuation { pending = $0 } }
        return target
    }
    var target: VoiceTarget { VoiceTarget(token: "synthetic", applicationID: "test.editor", deadline: 100) }
    func commit(_ text: String, target: VoiceTarget) async throws -> Bool { texts.append(text); return accept }
    func cancel(_ target: VoiceTarget?) {}
}
@MainActor private final class VoiceHarness {
    let recorder = RecordingDouble()
    let worker = WorkerDouble()
    let bridge = BridgeDouble()
    var allowed = true
    var held = true
    var pid: Int32? = 10
    var granted = true
    var validModel = true
    lazy var controller = VoiceInputController(recorder: recorder, worker: worker, bridge: bridge,
        environment: VoiceEnvironment(settings: { VoiceSettings() }, allowed: { self.allowed },
            pid: { self.pid }, held: { self.held }, microphoneGranted: { self.granted },
            validate: { _ in
                guard self.validModel else { throw VoiceFailure.model }
                return URL(fileURLWithPath: "/synthetic-model")
            }, shortcutEnabled: { true }), presentsHUD: false)
    func begin() async {
        controller.start(monitorEvents: false); controller.press()
        for _ in 0..<20 { await Task.yield() }
    }
    func recognize() async {
        held = false; controller.release()
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor @Test func voiceReleaseClosesMicBeforeRecognitionAndRejectedTicketRetainsCopy() async {
    let h = VoiceHarness()
    await h.begin()
    #expect(h.recorder.active)
    h.bridge.accept = false
    await h.recognize()
    #expect(!h.recorder.active)
    #expect(h.worker.pending != nil)
    h.worker.resolve("合成测试结果")
    for _ in 0..<20 { await Task.yield() }
    #expect(h.bridge.texts == ["合成测试结果"])
    #expect(h.controller.state.result == "合成测试结果")
    #expect(h.controller.state.phase == .failed)
    h.controller.stop()
}

@MainActor @Test func voiceCancelAndSecureInputDiscardLateRecognition() async {
    for secure in [false, true] {
        let h = VoiceHarness()
        await h.begin(); await h.recognize()
        if secure { h.allowed = false } else { h.controller.cancel() }
        h.worker.resolve("迟到的合成结果")
        for _ in 0..<20 { await Task.yield() }
        #expect(h.bridge.texts.isEmpty)
        #expect(h.controller.state.result.isEmpty)
        #expect(!h.recorder.active)
        h.controller.stop()
    }
}

@MainActor @Test func voiceTargetChangeAndInvalidModelNeverInsert() async {
    let changed = VoiceHarness()
    await changed.begin(); await changed.recognize()
    changed.pid = 11
    changed.worker.resolve("仅供复制的合成结果")
    for _ in 0..<20 { await Task.yield() }
    #expect(changed.bridge.texts.isEmpty)
    #expect(!changed.controller.state.result.isEmpty)
    changed.controller.stop()
    let invalid = VoiceHarness()
    invalid.validModel = false
    await invalid.begin(); await invalid.recognize()
    #expect(invalid.worker.prepared == 0)
    #expect(invalid.bridge.texts.isEmpty)
    invalid.controller.stop()
}

@MainActor @Test func voiceReleaseDuringCaptureAndMissingPermissionNeverOpenMic() async {
    let delayed = VoiceHarness()
    delayed.bridge.delayed = true
    await delayed.begin()
    delayed.held = false; delayed.controller.release()
    delayed.bridge.pending?.resume(returning: delayed.bridge.target); delayed.bridge.pending = nil
    for _ in 0..<20 { await Task.yield() }
    #expect(delayed.recorder.starts == 0)
    delayed.controller.stop()
    let denied = VoiceHarness()
    denied.granted = false
    await denied.begin()
    #expect(denied.recorder.starts == 0)
    denied.controller.stop()
}

@Test func voiceTicketRejectsChangedContextTimeoutAndReuse() {
    let context = VoiceCommitTicket.Context(activation: UUID(), applicationPID: 10, selection: NSRange(location: 0, length: 0))
    let changed = VoiceCommitTicket.Context(activation: UUID(), applicationPID: 10, selection: context.selection)
    var ticket = VoiceCommitTicket()
    let first = ticket.capture(context, now: 0)
    let changedAccepted = ticket.consume(first, context: changed, now: 1, deadline: 10)
    #expect(!changedAccepted)
    let second = ticket.capture(context, now: 0)
    let expiredAccepted = ticket.consume(second, context: context, now: 121, deadline: 200)
    #expect(!expiredAccepted)
    let third = ticket.capture(context, now: 0)
    let accepted = ticket.consume(third, context: context, now: 1, deadline: 10)
    #expect(accepted)
    let reused = ticket.consume(third, context: context, now: 1, deadline: 10)
    #expect(!reused)
}
