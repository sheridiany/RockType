import AppKit
import os
import Carbon
import RoarkTCore
import RoarkTPlatform

/// Own once in AppDelegate, call start()/stop(). No AppDelegate mutation is required here.
/// Input delivery is exclusively the authenticated IMK ticket path.
@MainActor final class VoiceInputController {
    private static let log = Logger(subsystem: "com.roarkist.roarkt", category: "voice")
    let state = VoiceHUDState()
    private let environment: VoiceEnvironment
    private let recorder: any VoiceRecording
    private let worker: any VoiceRecognizing
    private let bridge: any VoiceCommitting
    private let monitor = FnKeyMonitor()
    private var hud: VoiceHUDController?
    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var session = UUID()
    private let paste: any VoicePasting
    private var pasteTarget: VoicePasteTarget?
    private var insertionInvalidated = false
    private var target: VoiceTarget?
    private var sourcePID: Int32?
    private var recordingStarted: TimeInterval?
    private var running = false
    private(set) var monitoringAvailable = false
    private var globalKeys: Any?
    private var localKeys: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var deletionObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var inputSourceObserver: NSObjectProtocol?
    private var preparation: Task<Void, Never>?
    private var preparationID = UUID()
    private var preparedModel: VoiceModel?
    private var attemptedPreparation: String?
    private var observedSettings: VoiceSettings?
    private var idleTicks = 0
    private var dismissal: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewOffset = 0
    private var previewPolicy = VoicePreviewPolicy()
    private(set) var lastLatency: VoiceLatency?

    init(store: SettingsStore = .shared, models: VoiceModelStore = .shared,
         recorder: (any VoiceRecording)? = nil, worker: (any VoiceRecognizing)? = nil,
         bridge: (any VoiceCommitting)? = nil, paste: (any VoicePasting)? = nil, environment: VoiceEnvironment? = nil,
         presentsHUD: Bool = true) {
        self.environment = environment ?? .system(store: store, models: models)
        self.recorder = recorder ?? VoiceAudioCapture()
        self.worker = worker ?? VoiceWorkerClient()
        self.bridge = bridge ?? VoiceCommitBridge()
        self.paste = paste ?? VoicePasteBridge()
        if presentsHUD {
            hud = VoiceHUDController(state: state)
            hud?.onCancel = { [weak self] in self?.cancel() }
        }
    }

    func start(monitorEvents: Bool = true) {
        guard !running else { return }
        running = true
        if monitorEvents {
            monitor.onEvent = { [weak self] event in
                switch event {
                case .press: self?.press()
                case .release: self?.release()
                case .cancel: self?.cancel()
                }
            }
            do { try monitor.start(); monitoringAvailable = true } catch {
                monitoringAvailable = false
                show(.failed, "需要辅助功能权限；授权后重新启动语音监听。")
            }
            globalKeys = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.handleSourceEvent(event) }
            }
            localKeys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.handleSourceEvent(event) }
                return event
            }
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
                workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancel() }
                })
            }
        }
        if monitorEvents {
            settingsObserver = NotificationCenter.default.addObserver(forName: SettingsStore.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPreparation() }
            }
            inputSourceObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshPreparation() }
                }
            deletionObserver = NotificationCenter.default.addObserver(forName: VoiceModelStore.willDelete, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
        }
        refreshPreparation()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                self?.tick()
            }
        }
    }
    func stop() {
        running = false
        monitoringAvailable = false
        monitor.stop(); cancel()
        watchdog?.cancel(); watchdog = nil
        if let globalKeys { NSEvent.removeMonitor(globalKeys) }
        if let localKeys { NSEvent.removeMonitor(localKeys) }
        globalKeys = nil; localKeys = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers = []
        if let deletionObserver { NotificationCenter.default.removeObserver(deletionObserver) }
        deletionObserver = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let inputSourceObserver { DistributedNotificationCenter.default().removeObserver(inputSourceObserver) }
        settingsObserver = nil; inputSourceObserver = nil
    }

    func press() {
        guard running, environment.shortcutEnabled(), environment.allowed(), environment.held() else { return }
        let idle = ![.preparing, .loading, .recording, .recognizing, .polishing].contains(state.phase)
        let keepPrepared = idle && environment.settings().automaticallyPrepareModel && environment.inputSourceSelected() &&
            preparedModel == VoiceModel(environment.settings().model)
        reset(preservingPrepared: keepPrepared)
        guard environment.microphoneGranted() else {
            show(.failed, "请在设置 → 权限中允许麦克风，再按住 Fn。")
            return
        }
        guard environment.modelPresent(VoiceModel(environment.settings().model)) else {
            show(.failed, "请先在设置 → 语音下载模型。")
            return
        }
        guard let pid = environment.pid() else { return }
        sourcePID = pid
        pasteTarget = paste.capture(pid: pid)
        let id = session
        let model = VoiceModel(environment.settings().model)
        show(.preparing, "正在绑定输入位置…")
        task = Task { [weak self] in
            guard let self else { return }
            var startingMicrophone = false
            do {
                do {
                    let captured = try await bridge.capture(pid: pid)
                    guard session == id, !Task.isCancelled else { return }
                    target = captured
                } catch {
                    guard session == id, !Task.isCancelled else { return }
                    let reason = (error as? VoiceCaptureFailure)?.rawValue ?? ((error as? VoiceFailure) == .timeout ? "timeout" : "unavailable")
                    Self.log.notice("voice binding unavailable reason=\(reason, privacy: .public); recording continues")
                    bridge.cancel(nil)
                }
                guard environment.held(), environment.allowed(), environment.pid() == pid else { cancel(); return }
                if preparedModel != model {
                    show(.loading, "模型加载中…")
                    let directory = try await environment.validate(model)
                    guard session == id, !Task.isCancelled, environment.allowed() else { return }
                    try await worker.prepare(directory: directory)
                    guard session == id, !Task.isCancelled, environment.allowed() else { return }
                    preparedModel = model
                }
                guard environment.held(), environment.allowed(), environment.pid() == pid else { cancel(); return }
                startingMicrophone = true
                try recorder.start()
                recordingStarted = environment.now()
                show(.recording, "录音中 · 最长 3 分钟")
            } catch {
                guard session == id else { return }
                Self.log.error("voice preparation failed")
                recorder.cancel(); worker.stop(); preparedModel = nil
                bridge.cancel(target); target = nil; pasteTarget = nil
                show(.failed, startingMicrophone
                     ? "麦克风未能启动，请检查权限或录音设备。"
                     : "模型未就绪，请检查设置 → 语音中的下载与校验状态。")
            }
        }
    }
    func release() {
        guard running else { return }
        guard state.phase == .recording else {
            if [.preparing, .loading].contains(state.phase) { cancel() }
            return
        }
        let target = self.target
        let pasteTarget = self.pasteTarget
        // Close the microphone synchronously, before scheduling model work.
        let releasedAt = environment.now()
        let audio = recorder.finish()
        var latency = VoiceLatency()
        latency.stop = environment.now() - releasedAt
        latency.resamplingDuringCapture = recorder.resamplingSeconds
        let pendingPreview = previewTask
        recordingStarted = nil
        guard environment.allowed() else { cancel(); return }
        guard !audio.isEmpty else {
            bridge.cancel(target); self.target = nil; self.pasteTarget = nil
            showNoSpeech()
            return
        }
        let id = session
        show(.recognizing, "正在本机识别…")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var stage = environment.now()
                // Serialize behind the one bounded preview. Never cancel a healthy worker on
                // release (which would lose its warm model), and never commit preview text.
                await pendingPreview?.value
                latency.previewWait = environment.now() - stage
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                if preparedModel == nil {
                    stage = environment.now()
                    let model = VoiceModel(environment.settings().model)
                    let directory = try await environment.validate(model)
                    guard session == id, !Task.isCancelled, environment.allowed() else { return }
                    try await worker.prepare(directory: directory)
                    guard session == id, !Task.isCancelled, environment.allowed() else { return }
                    preparedModel = model
                    latency.modelRecovery = environment.now() - stage
                }
                stage = environment.now()
                let text = try await worker.transcribe(audio)
                latency.recognition = environment.now() - stage
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                stage = environment.now()
                let normalized = environment.settings().cleanUpLocally
                    ? VoiceTextCleaner.clean(text)
                    : text.trimmingCharacters(in: .whitespacesAndNewlines)
                latency.cleanup = environment.now() - stage
                guard !normalized.isEmpty else {
                    bridge.cancel(target); self.target = nil; self.pasteTarget = nil
                    if !environment.settings().automaticallyPrepareModel || !environment.inputSourceSelected() {
                        worker.stop(); preparedModel = nil
                    }
                    showNoSpeech()
                    return
                }
                state.result = normalized
                if environment.settings().polishWithAI { show(.polishing, "正在润色…") }
                stage = environment.now()
                let polished = await environment.polish(normalized)
                latency.polish = environment.now() - stage
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                state.result = polished
                let eligible = !insertionInvalidated && environment.pid() == sourcePID &&
                    VoiceInsertionPolicy.allowsAutomaticInsertion(text: polished, applicationID: target?.applicationID ?? pasteTarget?.applicationID)
                stage = environment.now()
                let accepted: Bool
                if eligible, let target {
                    // Never paste after an uncertain/rejected IMK commit: it may already have inserted.
                    accepted = (try? await bridge.commit(polished, target: target)) ?? false
                } else if eligible, let pasteTarget {
                    accepted = (try? await paste.paste(polished, target: pasteTarget, allowed: { [weak self] in
                        guard let self else { return false }
                        return self.session == id && !self.insertionInvalidated && self.environment.allowed() && self.environment.pid() == self.sourcePID
                    })) ?? false
                } else { accepted = false }
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                latency.commit = environment.now() - stage
                latency.total = environment.now() - releasedAt
                lastLatency = latency
                Self.log.info("voice timing stop=\(latency.stop) resample_during_capture=\(latency.resamplingDuringCapture) preview_wait=\(latency.previewWait) model_recovery=\(latency.modelRecovery) recognition=\(latency.recognition) cleanup=\(latency.cleanup) polish=\(latency.polish) commit=\(latency.commit) total=\(latency.total)")
                bridge.cancel(target); self.target = nil; self.pasteTarget = nil
                if !environment.settings().automaticallyPrepareModel || !environment.inputSourceSelected() {
                    worker.stop(); preparedModel = nil
                }
                if !accepted { Self.log.error("insertion not accepted (eligible \(eligible))") }
                show(accepted ? .done : .failed, accepted ? (target == nil ? "已请求粘贴 · 未发送消息" : "已填入 · 未发送") : "未能确认填入，请核对输入位置后复制结果。")
            } catch {
                guard session == id, !Task.isCancelled else { return }
                Self.log.error("voice recognition failed")
                worker.stop(); preparedModel = nil; bridge.cancel(target); self.target = nil; self.pasteTarget = nil
                if let failure = error as? VoiceFailure, failure == .empty {
                    showNoSpeech()
                } else {
                    show(.failed, (error as? VoiceFailure) == .timeout
                         ? "识别超时，请缩短录音后重试。"
                         : "识别未完成，请在设置 → 语音检查模型后重试。")
                }
            }
        }
    }
    func cancel() { reset(preservingPrepared: false) }

    /// Keystrokes/clicks invalidate the original destination even if the caret later returns.
    func sourceInputChanged() {
        guard [.preparing, .loading, .recording, .recognizing, .polishing].contains(state.phase) else { return }
        insertionInvalidated = true; pasteTarget = nil
    }
    private func handleSourceEvent(_ event: NSEvent) {
        guard !VoicePasteBridge.isOwnPaste(event) else { return }
        if event.type == .keyDown && event.keyCode == 53 { cancel() }
        else { sourceInputChanged() }
    }

    private func reset(preservingPrepared: Bool) {
        dismissal?.cancel(); dismissal = nil
        session = UUID()
        preparationID = UUID(); preparation?.cancel(); preparation = nil
        attemptedPreparation = nil
        task?.cancel(); task = nil
        previewTask?.cancel(); previewTask = nil; previewOffset = 0
        lastLatency = nil
        recorder.cancel(); bridge.cancel(target)
        if !preservingPrepared { worker.stop(); preparedModel = nil }
        target = nil; pasteTarget = nil; insertionInvalidated = false
        sourcePID = nil; recordingStarted = nil
        state.result = ""; state.phase = .hidden; state.message = ""
        state.levels = Array(repeating: 0.05, count: 9)
        hud?.hide()
    }
    func tick() {
        guard running else { return }
        idleTicks += 1
        if idleTicks >= 20 { idleTicks = 0; refreshPreparation() }
        guard state.phase != .hidden else { return }
        if !environment.allowed() {
            if [.preparing, .loading, .recording, .recognizing, .polishing].contains(state.phase) || !state.result.isEmpty { cancel() }
            return // Keep permission guidance visible; it contains no captured content.
        }
        if !environment.shortcutEnabled() { cancel(); return }
        if [.preparing, .loading].contains(state.phase), !environment.held() { cancel(); return }
        guard state.phase == .recording, let recordingStarted else { return }
        if !recorder.isRecording { cancel(); return }
        if !environment.held() { release(); return }
        if environment.pid() != sourcePID { cancel(); return }
        let elapsed = environment.now() - recordingStarted
        if elapsed >= Double(VoiceAudioSegmentation.maximumSeconds) || recorder.sampleCount >= VoiceAudioSegmentation.maximumSeconds * VoiceAudioSegmentation.sampleRate {
            release()
            if state.phase == .recognizing { show(.recognizing, "已达 3 分钟上限，正在识别…") }
            return
        }
        requestPreview()
        state.levels = Array(state.levels.dropFirst()) + [recorder.level]
    }
    private func requestPreview() {
        let model = VoiceModel(environment.settings().model)
        guard previewTask == nil, !previewPolicy.disabled.contains(model),
              environment.allowed(), let audio = recorder.preview(after: previewOffset) else { return }
        previewOffset += audio.count / MemoryLayout<Float>.size
        let id = session
        let start = environment.now()
        previewTask = Task { [weak self] in
            guard let self else { return }
            defer { if session == id { previewTask = nil } }
            do {
                _ = try await worker.preview(audio)
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                let elapsed = environment.now() - start
                previewPolicy.observe(model: model, seconds: elapsed, audioSeconds: Double(audio.count) / 64_000)
                Self.log.info("voice preview model=\(model.rawValue, privacy: .public) seconds=\(elapsed) audio_seconds=\(Double(audio.count) / 64_000) degraded=\(self.previewPolicy.disabled.contains(model))")
                // SPEC-015: retain bounded recognition/fallback behavior, discard interim text.
            } catch {
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                previewPolicy.fail(model: model)
                let elapsed = environment.now() - start
                let reason = (error as? VoiceFailure) == .timeout ? "timeout" : "unavailable"
                Self.log.info("voice preview stopped model=\(model.rawValue, privacy: .public) seconds=\(elapsed) reason=\(reason, privacy: .public)")
                // Real worker client tears down failed/timed-out work. Reload only after release.
                preparedModel = nil
            }
        }
    }

    /// Input-source/settings changes only load a verified local model. Never opens the mic.
    func refreshPreparation() {
        guard running else { return }
        let settings = environment.settings()
        if let previous = observedSettings, previous != settings { cancel() }
        observedSettings = settings
        let selected = environment.inputSourceSelected()
        let shouldPrepare = settings.automaticallyPrepareModel && selected
        let active = [.preparing, .loading, .recording, .recognizing, .polishing].contains(state.phase)
        if !shouldPrepare {
            // An in-flight dictation may finish; do not stop its worker merely on source change.
            if !active {
                preparationID = UUID(); preparation?.cancel(); preparation = nil
                if preparedModel != nil || attemptedPreparation != nil { worker.stop(); preparedModel = nil }
                attemptedPreparation = nil
            }
            return
        }
        let model = VoiceModel(settings.model)
        guard !active, !environment.held(), environment.modelPresent(model), preparedModel != model else { return }
        guard environment.allowed() else {
            if preparation != nil { cancel() }
            attemptedPreparation = nil
            return
        }
        let key = model.rawValue + ":" + String(environment.modelRevision())
        guard preparation == nil, attemptedPreparation != key else { return }
        attemptedPreparation = key
        let id = UUID(); preparationID = id
        preparation = Task { [weak self] in
            guard let self else { return }
            defer { if preparationID == id { preparation = nil } }
            do {
                let directory = try await environment.validate(model)
                guard preparationID == id, !Task.isCancelled, environment.allowed() else { return }
                try await worker.prepare(directory: directory)
                guard preparationID == id, !Task.isCancelled, environment.allowed() else { return }
                preparedModel = model
            } catch {
                guard preparationID == id else { return }
                worker.stop(); preparedModel = nil
            }
        }
    }

    private func showNoSpeech() {
        show(.noSpeech, "未检测到有效声音，请重试。")
        let id = session
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, session == id else { return }
            state.phase = .hidden; state.message = ""
            hud?.hide()
        }
    }

    private func show(_ phase: VoiceHUDState.Phase, _ message: String) {
        state.phase = phase; state.message = message; hud?.show()
    }
}
