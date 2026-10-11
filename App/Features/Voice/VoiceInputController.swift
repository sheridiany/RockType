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

    init(store: SettingsStore = .shared, models: VoiceModelStore = .shared,
         recorder: (any VoiceRecording)? = nil, worker: (any VoiceRecognizing)? = nil,
         bridge: (any VoiceCommitting)? = nil, environment: VoiceEnvironment? = nil,
         presentsHUD: Bool = true) {
        self.environment = environment ?? .system(store: store, models: models)
        self.recorder = recorder ?? VoiceAudioCapture()
        self.worker = worker ?? VoiceWorkerClient()
        self.bridge = bridge ?? VoiceCommitBridge()
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
            globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { MainActor.assumeIsolated { self?.cancel() } }
            }
            localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { MainActor.assumeIsolated { self?.cancel() } }
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
        let id = session
        let model = VoiceModel(environment.settings().model)
        show(.preparing, "正在绑定输入位置…")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let captured = try await bridge.capture(pid: pid)
                guard session == id, !Task.isCancelled else { return }
                target = captured
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
                try recorder.start()
                recordingStarted = ProcessInfo.processInfo.systemUptime
                show(.recording, "录音中")
            } catch {
                guard session == id else { return }
                Self.log.error("voice preparation failed")
                worker.stop(); preparedModel = nil
                bridge.cancel(target); target = nil
                show(.failed, state.phase == .loading
                     ? "模型未就绪，请检查设置 → 语音中的下载与校验状态。"
                     : "无法绑定输入位置，请选中 RockType 输入法后重试。")
            }
        }
    }
    func release() {
        guard running else { return }
        guard state.phase == .recording, let target else {
            if [.preparing, .loading].contains(state.phase) { cancel() }
            return
        }
        // Close the microphone synchronously, before scheduling model work.
        let audio = recorder.finish()
        recordingStarted = nil
        guard environment.allowed() else { cancel(); return }
        guard !audio.isEmpty else {
            bridge.cancel(target); self.target = nil
            showNoSpeech()
            return
        }
        let id = session
        show(.recognizing, "正在本机识别…")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await worker.transcribe(audio)
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                let normalized = environment.settings().cleanUpLocally
                    ? VoiceTextCleaner.clean(text)
                    : text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    bridge.cancel(target); self.target = nil
                    if !environment.settings().automaticallyPrepareModel || !environment.inputSourceSelected() {
                        worker.stop(); preparedModel = nil
                    }
                    showNoSpeech()
                    return
                }
                state.result = normalized
                if environment.settings().polishWithAI { show(.polishing, "正在润色…") }
                let polished = await environment.polish(normalized)
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                state.result = polished
                let eligible = environment.pid() == sourcePID &&
                    VoiceInsertionPolicy.allowsAutomaticInsertion(text: polished, applicationID: target.applicationID)
                let accepted = eligible ? ((try? await bridge.commit(polished, target: target)) ?? false) : false
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                bridge.cancel(target); self.target = nil
                if !environment.settings().automaticallyPrepareModel || !environment.inputSourceSelected() {
                    worker.stop(); preparedModel = nil
                }
                if !accepted { Self.log.error("insertion not accepted (eligible \(eligible))") }
                show(accepted ? .done : .failed, accepted ? "已填入 · 未发送" : "输入位置已变化或提交超时，请复制结果。")
            } catch {
                guard session == id, !Task.isCancelled else { return }
                Self.log.error("voice recognition failed")
                worker.stop(); preparedModel = nil; bridge.cancel(target); self.target = nil
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

    private func reset(preservingPrepared: Bool) {
        dismissal?.cancel(); dismissal = nil
        session = UUID()
        preparationID = UUID(); preparation?.cancel(); preparation = nil
        attemptedPreparation = nil
        task?.cancel(); task = nil
        recorder.cancel(); bridge.cancel(target)
        if !preservingPrepared { worker.stop(); preparedModel = nil }
        target = nil; sourcePID = nil; recordingStarted = nil
        state.result = ""; state.phase = .hidden; state.message = ""
        state.seconds = 0; state.levels = Array(repeating: 0.05, count: 9)
        hud?.hide()
    }
    private func tick() {
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
        let elapsed = ProcessInfo.processInfo.systemUptime - recordingStarted
        if elapsed >= 60 { cancel(); return }
        state.seconds = Int(elapsed)
        state.levels.removeFirst(); state.levels.append(recorder.level)
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
        let key = model.rawValue + ":" + String(environment.modelRevision())
        guard preparation == nil, attemptedPreparation != key else { return }
        attemptedPreparation = key
        let id = UUID(); preparationID = id
        preparation = Task { [weak self] in
            guard let self else { return }
            defer { if preparationID == id { preparation = nil } }
            do {
                let directory = try await environment.validate(model)
                guard preparationID == id, !Task.isCancelled else { return }
                try await worker.prepare(directory: directory)
                guard preparationID == id, !Task.isCancelled else { return }
                preparedModel = model
            } catch {
                guard preparationID == id else { return }
                worker.stop(); preparedModel = nil
            }
        }
    }

    private func showNoSpeech() {
        show(.failed, "未检测到有效声音，请重试。")
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
