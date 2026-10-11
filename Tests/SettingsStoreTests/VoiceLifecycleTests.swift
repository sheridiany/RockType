import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class RecordingDouble: VoiceRecording {
    var level: Double = 0.5
    var active = false
    var isRecording: Bool { active }
    var starts = 0
    var audio = Data(repeating: 0, count: 64)
    var sampleCount = 0
    var enablePreviews = false
    func preview(after offset: Int) -> Data? {
        let bytes = VoiceAudioSegmentation.previewSeconds * 64_000
        guard enablePreviews, offset * 4 + bytes <= audio.count else { return nil }
        return audio.subdata(in: (offset * 4)..<(offset * 4 + bytes))
    }
    func start() throws { starts += 1; active = true }
    func finish() -> Data { active = false; return audio }
    func cancel() { active = false }
}
@MainActor private final class WorkerDouble: VoiceRecognizing {
    var stopped = 0
    var prepared = 0
    var preparation: CheckedContinuation<Void, any Error>?
    var delayPreparation = false
    var pending: CheckedContinuation<String, any Error>?
    var previewPending: CheckedContinuation<String, any Error>?
    var previewCalls = 0
    var finalAudio: Data?
    func preview(_ audio: Data) async throws -> String {
        previewCalls += 1
        return try await withCheckedThrowingContinuation { previewPending = $0 }
    }
    func resolvePreview(_ text: String) { previewPending?.resume(returning: text); previewPending = nil }
    func prepare(directory: URL) async throws {
        prepared += 1
        if delayPreparation { try await withCheckedThrowingContinuation { preparation = $0 } }
    }
    func transcribe(_ audio: Data) async throws -> String {
        finalAudio = audio
        return try await withCheckedThrowingContinuation { pending = $0 }
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
    var present = true
    var settings = VoiceSettings()
    var now = 1000.0
    var selected = false
    var polish: @MainActor (String) async -> String = { $0 }
    lazy var controller = VoiceInputController(recorder: recorder, worker: worker, bridge: bridge,
        environment: VoiceEnvironment(settings: { self.settings }, allowed: { self.allowed },
            pid: { self.pid }, held: { self.held }, microphoneGranted: { self.granted },
            validate: { _ in
                guard self.validModel else { throw VoiceFailure.model }
                return URL(fileURLWithPath: "/synthetic-model")
            }, shortcutEnabled: { true }, modelPresent: { _ in self.present }, inputSourceSelected: { self.selected },
            now: { self.now }, polish: { await self.polish($0) }), presentsHUD: false)
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
    #expect(h.bridge.texts == ["合成测试结果。"])
    #expect(h.controller.state.result == "合成测试结果。")
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
    #expect(invalid.recorder.starts == 0)
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

@MainActor @Test func voicePreparationDoesNotRecordReusesWarmModelAndReleasesWhenDisabled() async {
    let h = VoiceHarness()
    h.settings.automaticallyPrepareModel = true
    h.selected = true; h.held = false
    h.controller.start(monitorEvents: false)
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.prepared == 1)
    #expect(h.recorder.starts == 0)
    h.held = true; h.controller.press()
    for _ in 0..<30 { await Task.yield() }
    await h.recognize()
    #expect(h.worker.prepared == 1)
    h.worker.resolve("预加载路径合成结果")
    for _ in 0..<30 { await Task.yield() }
    let stopped = h.worker.stopped
    h.settings.automaticallyPrepareModel = false
    h.controller.refreshPreparation()
    #expect(h.worker.stopped > stopped)
    #expect(!h.recorder.active)
    h.controller.stop()
}

@MainActor @Test func voicePreparationWaitsForSelectedSourceAndReloadsNewModel() async {
    let h = VoiceHarness()
    h.settings.automaticallyPrepareModel = true; h.held = false
    h.controller.start(monitorEvents: false)
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.prepared == 0)
    h.selected = true; h.controller.refreshPreparation()
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.prepared == 1)
    h.settings.model = .large; h.controller.refreshPreparation()
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.prepared == 2)
    #expect(h.recorder.starts == 0)
    h.controller.stop()
}

@MainActor @Test func voiceCancellationDuringPolishCannotCommitLateAIResult() async {
    let h = VoiceHarness()
    var pending: CheckedContinuation<String, Never>?
    h.settings.polishWithAI = true
    h.polish = { _ in await withCheckedContinuation { pending = $0 } }
    await h.begin(); await h.recognize()
    h.worker.resolve("AI 前的合成原文")
    for _ in 0..<30 { await Task.yield() }
    #expect(pending != nil)
    #expect(h.controller.state.phase == .polishing)
    h.controller.cancel()
    pending?.resume(returning: "迟到的 AI 合成文本")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.bridge.texts.isEmpty)
    #expect(h.controller.state.result.isEmpty)
    h.controller.stop()
}

@MainActor @Test func voiceNewHoldStopsBusyWorkerEvenWithAutomaticPreparation() async {
    let h = VoiceHarness()
    h.settings.automaticallyPrepareModel = true; h.selected = true
    await h.begin(); await h.recognize()
    let stopped = h.worker.stopped
    h.held = true; h.controller.press()
    #expect(h.worker.stopped > stopped)
    h.worker.resolve("上一轮合成结果")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.bridge.texts.isEmpty)
    #expect(h.controller.state.phase == .recording)
    h.controller.stop()
}

@MainActor @Test func voiceColdLoadDoesNotOpenMicAndReleaseDiscardsLateLoad() async {
    let h = VoiceHarness()
    h.worker.delayPreparation = true
    await h.begin()
    #expect(h.controller.state.phase == .loading)
    #expect(h.controller.state.message == "模型加载中…")
    #expect(h.recorder.starts == 0)
    h.held = false; h.controller.release()
    h.worker.preparation?.resume(); h.worker.preparation = nil
    for _ in 0..<30 { await Task.yield() }
    #expect(h.recorder.starts == 0)
    #expect(h.controller.state.phase == .hidden)
    h.controller.stop()
}

@MainActor @Test func voiceMissingModelNeverRecords() async {
    let h = VoiceHarness()
    h.present = false
    await h.begin()
    #expect(h.recorder.starts == 0)
    #expect(h.worker.prepared == 0)
    #expect(h.controller.state.phase == .failed)
    h.controller.stop()
}

@MainActor @Test func voiceEmptyRecognitionDismissesWithoutModelError() async throws {
    let h = VoiceHarness()
    await h.begin(); await h.recognize()
    #expect(h.controller.state.phase == .recognizing)
    h.worker.resolve("  ")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.controller.state.message == "未检测到有效声音，请重试。")
    #expect(h.bridge.texts.isEmpty)
    try await Task.sleep(for: .milliseconds(2200))
    #expect(h.controller.state.phase == .hidden)
    h.controller.stop()
}

@MainActor @Test func voiceCleanupSwitchAndPolishFallbackUseSameText() async {
    for enabled in [true, false] {
        let h = VoiceHarness()
        h.settings.cleanUpLocally = enabled
        h.settings.polishWithAI = true
        var received = ""
        h.polish = { text in received = text; return text }
        await h.begin(); await h.recognize()
        h.worker.resolve("嗯，合成  测试")
        for _ in 0..<30 { await Task.yield() }
        let expected = enabled ? "合成 测试。" : "嗯，合成  测试"
        #expect(received == expected)
        #expect(h.bridge.texts == [expected])
        h.controller.stop()
    }
}

@MainActor @Test func voiceFillerOnlyResultDoesNotPolishOrInsert() async {
    let h = VoiceHarness()
    var calls = 0
    h.polish = { text in calls += 1; return text }
    await h.begin(); await h.recognize()
    h.worker.resolve("嗯，呃。")
    for _ in 0..<30 { await Task.yield() }
    #expect(calls == 0)
    #expect(h.bridge.texts.isEmpty)
    #expect(h.controller.state.message == "未检测到有效声音，请重试。")
    h.controller.stop()
}


@MainActor @Test func voiceWorkerErrorsGiveSpecificRecoveryWithoutInserting() async {
    for (failure, message) in [(VoiceFailure.empty, "未检测到有效声音，请重试。"), (.timeout, "识别超时，请缩短录音后重试。"), (.unavailable, "识别未完成，请在设置 → 语音检查模型后重试。")] {
        let h = VoiceHarness()
        await h.begin(); await h.recognize()
        h.worker.pending?.resume(throwing: failure)
        h.worker.pending = nil
        for _ in 0..<30 { await Task.yield() }
        #expect(h.controller.state.phase == .failed)
        #expect(h.controller.state.message == message)
        #expect(h.bridge.texts.isEmpty)
        #expect(h.controller.state.result.isEmpty)
        h.controller.stop()
    }
}

@MainActor @Test func voicePreviewIsDisplayOnlyAndFinalReprocessesAllAudio() async {
    let h = VoiceHarness()
    h.recorder.audio = Data(repeating: 1, count: 12 * 64_000)
    h.recorder.enablePreviews = true
    await h.begin(); h.controller.tick()
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.previewCalls == 1)
    for _ in 0..<10 { h.controller.tick() }
    #expect(h.worker.previewCalls == 1, "Never enqueue a backlog")
    h.now += 0.2; h.worker.resolvePreview("临时预览，")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.controller.state.preview == "临时预览，")
    #expect(h.controller.state.result.isEmpty && h.bridge.texts.isEmpty)
    h.controller.tick()
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.previewCalls == 2)
    await h.recognize()
    #expect(!h.recorder.active && h.worker.pending == nil, "Stop capture first; serialize behind preview")
    h.worker.resolvePreview("松键后迟到的预览")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.controller.state.preview.isEmpty)
    #expect(h.worker.finalAudio == h.recorder.audio, "Final pass includes already previewed audio")
    h.worker.resolve("最终的完整结果。")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.bridge.texts == ["最终的完整结果。"])
    #expect(h.controller.lastLatency != nil)
    h.controller.stop()
}

@MainActor @Test func voiceSlowPreviewDegradesWithoutStoppingCaptureOrLosingFinal() async {
    let h = VoiceHarness()
    h.recorder.enablePreviews = true; h.recorder.audio = Data(repeating: 1, count: 18 * 64_000)
    await h.begin(); h.controller.tick()
    for _ in 0..<30 { await Task.yield() }
    h.now += 2.5 // RTF > 0.8 within the 3s preview deadline
    h.worker.resolvePreview("慢速预览")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.recorder.active)
    #expect(h.controller.state.previewStatus.contains("跟不上"))
    h.controller.tick()
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.previewCalls == 1)
    await h.recognize(); h.worker.resolve("降级后的完整结果。")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.bridge.texts == ["降级后的完整结果。"])
    h.held = true; h.controller.press()
    for _ in 0..<30 { await Task.yield() }
    h.controller.tick()
    #expect(h.worker.previewCalls == 1, "Remember slow model for this process")
    h.controller.stop()
}

@MainActor @Test func voicePreviewTimeoutRecoversModelOnReleaseAndSecurityDiscardsLateText() async {
    for secure in [false, true] {
        let h = VoiceHarness()
        h.recorder.enablePreviews = true; h.recorder.audio = Data(repeating: 1, count: 6 * 64_000)
        await h.begin(); h.controller.tick()
        for _ in 0..<30 { await Task.yield() }
        if secure {
            h.allowed = false; h.controller.tick()
            h.worker.resolvePreview("不得显示的迟到预览")
        } else {
            h.worker.previewPending?.resume(throwing: VoiceFailure.timeout); h.worker.previewPending = nil
        }
        for _ in 0..<30 { await Task.yield() }
        #expect(h.controller.state.preview.isEmpty && h.bridge.texts.isEmpty)
        if !secure {
            #expect(h.recorder.active)
            await h.recognize()
            #expect(h.worker.prepared == 2)
            h.worker.resolve("恢复后的结果。")
            for _ in 0..<30 { await Task.yield() }
            #expect(h.bridge.texts == ["恢复后的结果。"])
        } else { #expect(!h.recorder.active) }
        h.controller.stop()
    }
}

@MainActor @Test func voiceLengthLimitFinalizesInsteadOfDiscardingAudio() async {
    let h = VoiceHarness()
    await h.begin()
    h.now += 180; h.controller.tick()
    #expect(!h.recorder.active)
    #expect(h.controller.state.message.contains("3 分钟上限"))
    for _ in 0..<30 { await Task.yield() }
    h.worker.resolve("长录音末尾仍然保留。")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.bridge.texts == ["长录音末尾仍然保留。"])
    h.controller.stop()
}

@MainActor @Test func voiceNewSessionCannotBeOverwrittenByOldPreviewOrLoseItsInFlightGuard() async throws {
    let h = VoiceHarness()
    h.recorder.enablePreviews = true; h.recorder.audio = Data(repeating: 1, count: 12 * 64_000)
    await h.begin(); h.controller.tick()
    for _ in 0..<30 { await Task.yield() }
    let old = try #require(h.worker.previewPending)
    h.worker.previewPending = nil
    h.controller.press()
    for _ in 0..<30 { await Task.yield() }
    h.controller.tick()
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.previewCalls == 2)
    old.resume(returning: "上一次录音的迟到文字")
    for _ in 0..<30 { await Task.yield() }
    h.controller.tick()
    #expect(h.worker.previewCalls == 2, "Old defer must not clear the new in-flight task")
    #expect(h.controller.state.preview.isEmpty)
    h.worker.resolvePreview("新的会话预览")
    for _ in 0..<30 { await Task.yield() }
    #expect(h.controller.state.preview == "新的会话预览")
    #expect(h.bridge.texts.isEmpty)
    h.controller.stop()
}

@Test func voicePreviewBudgetsAreSeparateForEachModel() {
    var policy = VoicePreviewPolicy()
    policy.observe(model: .small, seconds: 5, audioSeconds: 6)
    policy.observe(model: .large, seconds: 0.3, audioSeconds: 6)
    #expect(policy.disabled.contains(.small))
    #expect(!policy.disabled.contains(.large))
    policy.fail(model: .large)
    #expect(policy.disabled.contains(.large))
}

@MainActor @Test func voiceProtectedInputDoesNotStartBackgroundModelWarmup() async {
    let h = VoiceHarness()
    h.settings.automaticallyPrepareModel = true; h.selected = true; h.held = false; h.allowed = false
    h.controller.start(monitorEvents: false)
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.prepared == 0 && h.recorder.starts == 0)
    h.allowed = true; h.controller.refreshPreparation()
    for _ in 0..<30 { await Task.yield() }
    #expect(h.worker.prepared == 1 && h.recorder.starts == 0)
    h.controller.stop()
}
