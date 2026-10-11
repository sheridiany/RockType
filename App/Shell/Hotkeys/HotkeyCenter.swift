import AppKit
import Observation
import RoarkTCore
import RoarkTPlatform

@MainActor protocol HotkeyRegistering: AnyObject {
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) throws
    func stop()
}

@MainActor final class SystemHotkeyRegistrar: HotkeyRegistering {
    private let keys = GlobalHotkeys()
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) throws {
        try keys.register(shortcut, handler: handler)
    }
    func stop() { keys.stop() }
}

/// Inject SettingsStore read/write closures. Observation tracks reads inside `readSettings`,
/// so external edits re-register too, without making S3 depend on Store implementation.
@MainActor @Observable final class HotkeyCenter {
    enum Action: String, CaseIterable, Identifiable {
        case voiceHoldToTalk, screenshot, translateSelection, summarizeSelection, screenshotHistory, togglePins, closePins, nextPin, showSettings
        var id: Self { self }
        var title: String {
            switch self {
            case .voiceHoldToTalk: "按住说话"
            case .screenshot: "截图"
            case .translateSelection: "翻译选区"
            case .summarizeSelection: "总结选区"
            case .screenshotHistory: "截图历史"
            case .togglePins: "隐藏／显示全部贴图"
            case .closePins: "关闭全部贴图"
            case .nextPin: "切换到下一张贴图"
            case .showSettings: "显示设置"
            }
        }
        var core: ShortcutAction? { ShortcutAction(rawValue: rawValue) }
    }
    enum Status: Equatable {
        case unassigned, registered, conflict, unsupported, needsAccessibility, unavailable, system(Int32), recording
        var text: String {
            switch self {
            case .unassigned: "未设置"
            case .registered: "已注册"
            case .conflict: "快捷键冲突，请重新录制"
            case .unsupported: "不支持此组合；请使用 Control、Option 或 Command 加按键，语音仅支持 Fn"
            case .needsAccessibility: "Fn 监听需要辅助功能权限"
            case .unavailable: "系统监听不可用，请重试"
            case .system: "系统注册失败，请重试或更换组合键"
            case .recording: "录制期间已暂停快捷键"
            }
        }
    }
    private(set) var settings = ShortcutSettings()
    private(set) var statuses: [Action: Status] = [:]
    private(set) var recording: Action?
    private(set) var notice: String?
    @ObservationIgnored var screenshotAction: (@MainActor () -> Void)?
    @ObservationIgnored private let registrar: any HotkeyRegistering
    @ObservationIgnored private let readSettings: @MainActor () -> ShortcutSettings
    @ObservationIgnored private let writeSettings: @MainActor (ShortcutSettings) -> Void
    @ObservationIgnored private let showSettings: @MainActor () -> Void
    @ObservationIgnored private let unavailableAction: @MainActor (Action) -> Void
    @ObservationIgnored private let selection: @MainActor (ShortcutAction) -> Void
    @ObservationIgnored private let voiceListening: @MainActor (Bool) -> Bool
    @ObservationIgnored private var voiceEnabled = false
    @ObservationIgnored private let allowed: @MainActor () -> Bool
    @ObservationIgnored private let trusted: @MainActor () -> Bool
    @ObservationIgnored private var running = false
    @ObservationIgnored private var observationGeneration = 0
    @ObservationIgnored private var registrationGeneration = 0
    @ObservationIgnored private var lastTrusted = false
    @ObservationIgnored private var permissionTask: Task<Void, Never>?

    init(read: @escaping @MainActor () -> ShortcutSettings,
         write: @escaping @MainActor (ShortcutSettings) -> Void,
         showSettings: @escaping @MainActor () -> Void,
         unavailableAction: @escaping @MainActor (Action) -> Void = { _ in },
         selection: @escaping @MainActor (ShortcutAction) -> Void = { _ in },
         registrar: (any HotkeyRegistering)? = nil,
         allowed: @escaping @MainActor () -> Bool = { SecureInput.status() == .allowed },
         trusted: @escaping @MainActor () -> Bool = { Accessibility.isTrusted() },
         voiceListening: @escaping @MainActor (Bool) -> Bool = { _ in true }) {
        self.readSettings = read; self.writeSettings = write; self.showSettings = showSettings
        self.unavailableAction = unavailableAction; self.selection = selection
        self.registrar = registrar ?? SystemHotkeyRegistrar()
        self.allowed = allowed; self.trusted = trusted; self.voiceListening = voiceListening
        settings = read()
    }

    func start() {
        guard !running else { return }
        running = true
        observeSettings()
        lastTrusted = trusted()
        permissionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                self?.refreshPermissions()
            }
        }
    }

    func refreshPermissions() {
        guard running else { return }
        let current = trusted()
        if current != lastTrusted { lastTrusted = current; retry() }
    }

    func stop() {
        running = false; observationGeneration += 1; registrationGeneration += 1
        permissionTask?.cancel(); permissionTask = nil
        registrar.stop(); recording = nil; statuses = [:]
        suspendVoice()
    }

    private func observeSettings() {
        guard running else { return }
        observationGeneration += 1
        let generation = observationGeneration
        let updated = withObservationTracking { readSettings() } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.observationGeneration == generation else { return }
                self.observeSettings()
            }
        }
        settings = updated
        registerAll()
    }

    private static let groupActions: [ShortcutAction] = [.screenshotHistory, .togglePins, .closePins, .nextPin]
    var screenshotGroupAction: (Action) -> Void = { _ in }
    func shortcut(for action: Action) -> Shortcut? {
        if let core = action.core {
            if Self.groupActions.contains(core), settings.screenshotGroupDefaultsApplied != true {
                return settings.bindings[core] ?? Shortcut.defaults[core]
            }
            return settings.bindings[core]
        }
        return settings.showSettings
    }

    func set(_ shortcut: Shortcut?, for action: Action) {
        var updated = readSettings()
        if let core = action.core, Self.groupActions.contains(core), updated.screenshotGroupDefaultsApplied != true {
            for action in Self.groupActions where updated.bindings[action] == nil { updated.bindings[action] = Shortcut.defaults[action] }
            updated.screenshotGroupDefaultsApplied = true
        }
        if let core = action.core { updated.bindings[core] = shortcut }
        else { updated.showSettings = shortcut }
        writeSettings(updated)
        recording = nil
        settings = updated
        // Re-arm now, invalidating the callback queued by the write.
        observeSettings()
    }

    func restoreDefault(for action: Action) {
        set(action.core.flatMap { Shortcut.defaults[$0] }, for: action)
    }

    func beginRecording(_ action: Action) {
        recording = action; registrationGeneration += 1; registrar.stop()
        suspendVoice()
        statuses = Dictionary(uniqueKeysWithValues: Action.allCases.map { ($0, .recording) })
    }
    func cancelRecording() { recording = nil; retry() }
    func retry() {
        settings = readSettings()
        suspendVoice()
        registerAll()
    }

    private func registerAll() {
        guard running, recording == nil else { return }
        registrationGeneration += 1
        let generation = registrationGeneration
        registrar.stop(); statuses = [:]
        for action in Action.allCases {
            guard let shortcut = shortcut(for: action) else { statuses[action] = .unassigned; continue }
            let duplicate = Action.allCases.contains { other in
                guard other != action, let candidate = self.shortcut(for: other) else { return false }
                return candidate.modifiers == shortcut.modifiers && candidate.key?.lowercased() == shortcut.key?.lowercased()
            }
            guard !duplicate else { statuses[action] = .conflict; continue }
            let handler: @MainActor () -> Void = { [weak self] in
                guard let self, self.running, self.registrationGeneration == generation, self.recording == nil else { return }
                if action == .showSettings { self.showSettings(); return }
                guard self.allowed() else { return }
                if let core = action.core, Self.groupActions.contains(core) {
                    self.screenshotGroupAction(action)
                } else if action == .screenshot {
                    if let screenshotAction = self.screenshotAction { screenshotAction() }
                    else { self.notice = "截图尚未接入，请重新启动应用。" }
                } else if action == .translateSelection || action == .summarizeSelection, let core = action.core {
                    self.notice = nil
                    self.selection(core)
                } else {
                    self.notice = "\(action.title)即将推出；当前仅验证快捷键。"
                    self.unavailableAction(action)
                }
            }
            do {
                if action == .voiceHoldToTalk {
                    guard shortcut.key == nil, shortcut.modifiers == .function else {
                        statuses[action] = .unsupported; continue
                    }
                    guard trusted() else { statuses[action] = .needsAccessibility; continue }
                    // VoiceInputController alone owns press/release/cancel monitoring.
                    statuses[action] = .registered
                    continue
                } else {
                    guard !shortcut.modifiers.intersection([.control, .option, .command]).isEmpty else {
                        statuses[action] = .unsupported; continue
                    }
                    try registrar.register(shortcut, handler: handler)
                }
                statuses[action] = .registered
            } catch GlobalHotkeys.Failure.conflict { statuses[action] = .conflict }
              catch GlobalHotkeys.Failure.unsupportedShortcut { statuses[action] = .unsupported }
              catch GlobalHotkeys.Failure.system(let code) { statuses[action] = .system(code) }
              catch { statuses[action] = .unavailable }
        }
        let shouldListen = statuses[.voiceHoldToTalk] == .registered
        if shouldListen && !voiceEnabled {
            voiceEnabled = voiceListening(true)
            if !voiceEnabled { statuses[.voiceHoldToTalk] = .unavailable }
        } else if !shouldListen { suspendVoice() }
    }

    private func suspendVoice() {
        if voiceEnabled { _ = voiceListening(false) }
        voiceEnabled = false
    }

    isolated deinit {
        permissionTask?.cancel(); registrar.stop()
        if voiceEnabled { _ = voiceListening(false) }
    }
}
