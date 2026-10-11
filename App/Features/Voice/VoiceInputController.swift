import AppKit
import AVFoundation
import RoarkTCore
import RoarkTPlatform

@MainActor struct VoiceEnvironment {
    var settings: () -> VoiceSettings
    var allowed: () -> Bool
    var pid: () -> Int32?
    var held: () -> Bool
    var microphoneGranted: () -> Bool
    var validate: @MainActor (VoiceModel) async throws -> URL
    var shortcutEnabled: () -> Bool
    var modelPresent: (VoiceModel) -> Bool = { _ in true }

    static func system(store: SettingsStore, models: VoiceModelStore) -> Self {
        Self(settings: { store.settings.voice }, allowed: { SecureInput.status() == .allowed },
             pid: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
             held: { NSEvent.modifierFlags.contains(.function) },
             microphoneGranted: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
             validate: { try await models.validate($0) },
             shortcutEnabled: { store.settings.shortcuts.bindings[.voiceHoldToTalk] == Shortcut(key: nil, modifiers: .function) },
             modelPresent: { models.isPresent($0) })
    }
}

/// Own once in AppDelegate, call start()/stop(). No AppDelegate mutation is required here.
/// Input delivery is exclusively the authenticated IMK ticket path.
@MainActor final class VoiceInputController {
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
    private var globalKeys: Any?
    private var localKeys: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var deletionObserver: NSObjectProtocol?

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
            do { try monitor.start() } catch {
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
        deletionObserver = NotificationCenter.default.addObserver(forName: VoiceModelStore.willDelete, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                self?.tick()
            }
        }
    }
    func stop() {
        running = false
        monitor.stop(); cancel()
        watchdog?.cancel(); watchdog = nil
        if let globalKeys { NSEvent.removeMonitor(globalKeys) }
        if let localKeys { NSEvent.removeMonitor(localKeys) }
        globalKeys = nil; localKeys = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers = []
        if let deletionObserver { NotificationCenter.default.removeObserver(deletionObserver) }
        deletionObserver = nil
    }

    func press() {
        guard running, environment.shortcutEnabled(), environment.allowed(), environment.held() else { return }
        cancel()
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
        show(.preparing, "正在绑定输入位置…")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let captured = try await bridge.capture(pid: pid)
                guard session == id, !Task.isCancelled else { return }
                target = captured
                guard environment.held(), environment.allowed(), environment.pid() == pid else { cancel(); return }
                try recorder.start()
                recordingStarted = ProcessInfo.processInfo.systemUptime
                show(.recording, "录音中")
            } catch {
                guard session == id else { return }
                bridge.cancel(target); target = nil
                show(.failed, "无法绑定输入位置，请选中 RoarkT 输入法后重试。")
            }
        }
    }
    func release() {
        guard running else { return }
        guard state.phase == .recording, let target else {
            if state.phase == .preparing { cancel() }
            return
        }
        // Close the microphone synchronously, before scheduling model work.
        let audio = recorder.finish()
        recordingStarted = nil
        guard environment.allowed() else { cancel(); return }
        guard !audio.isEmpty else {
            bridge.cancel(target); self.target = nil
            show(.failed, "未检测到有效声音，请重试。")
            return
        }
        let id = session
        let model = VoiceModel(environment.settings().model)
        show(.recognizing, "正在本机识别…")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let directory = try await environment.validate(model)
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                try await worker.prepare(directory: directory)
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                let text = try await worker.transcribe(audio)
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { throw VoiceFailure.empty }
                state.result = normalized
                let eligible = environment.pid() == sourcePID &&
                    VoiceInsertionPolicy.allowsAutomaticInsertion(text: normalized, applicationID: target.applicationID)
                let accepted = eligible ? ((try? await bridge.commit(normalized, target: target)) ?? false) : false
                guard session == id, !Task.isCancelled, environment.allowed() else { return }
                bridge.cancel(target); self.target = nil
                worker.stop()
                show(accepted ? .done : .failed, accepted ? "已填入 · 未发送" : "输入位置已变化或提交超时，请复制结果。")
            } catch {
                guard session == id, !Task.isCancelled else { return }
                worker.stop(); bridge.cancel(target); self.target = nil
                show(.failed, "识别未完成，请检查模型下载与校验状态后重试。")
            }
        }
    }
    func cancel() {
        session = UUID()
        task?.cancel(); task = nil
        recorder.cancel(); worker.stop(); bridge.cancel(target)
        target = nil; sourcePID = nil; recordingStarted = nil
        state.result = ""; state.phase = .hidden; state.message = ""
        hud?.hide()
    }
    private func tick() {
        guard running else { return }
        if !environment.allowed() || !environment.shortcutEnabled() {
            if state.phase != .hidden { cancel() }
            return
        }
        if state.phase == .preparing, !environment.held() { cancel(); return }
        guard state.phase == .recording, let recordingStarted else { return }
        if !recorder.isRecording { cancel(); return }
        if !environment.held() { release(); return }
        if environment.pid() != sourcePID { cancel(); return }
        let elapsed = ProcessInfo.processInfo.systemUptime - recordingStarted
        if elapsed >= 60 { cancel(); return }
        state.seconds = Int(elapsed)
        state.levels.removeFirst(); state.levels.append(recorder.level)
    }
    private func show(_ phase: VoiceHUDState.Phase, _ message: String) {
        state.phase = phase; state.message = message; hud?.show()
    }
}
