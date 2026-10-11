import AppKit
import Carbon
import Observation
import RoarkTCore

struct InputSourceSnapshot: Equatable {
    var addedIDs: Set<String>
    var selectedID: String?

    static let supportedIDs: Set<String> = [Identifiers.pinyinInputSourceID, Identifiers.flypyInputSourceID]
    var selectedRoarkTID: String? {
        guard let selectedID, addedIDs.contains(selectedID), Self.supportedIDs.contains(selectedID) else { return nil }
        return selectedID
    }

    @MainActor static func current() -> Self {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as? [TISInputSource] ?? []
        let added = sources.compactMap { source -> String? in
            guard let id = string(source, kTISPropertyInputSourceID), supportedIDs.contains(id),
                  let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(enabled).takeUnretainedValue()) else { return nil }
            return id
        }
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return Self(addedIDs: Set(added), selectedID: string(current, kTISPropertyInputSourceID))
    }

    fileprivate static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
}

/// Only an increasing counter on the same connection, for the same selected source,
/// may confirm input. Connection replacement/reset requires a new baseline.
struct InputVerificationEvidence {
    let sourceID: String
    let baseline: TranslationServiceClient.InputGeneration

    func accepts(_ current: TranslationServiceClient.InputGeneration, source: InputSourceSnapshot) -> Bool {
        source.selectedRoarkTID == sourceID && current.connectionID == baseline.connectionID && current.value > baseline.value
    }
}

@MainActor @Observable
final class InputSourceManager {
    private(set) var snapshot = InputSourceSnapshot(addedIDs: [], selectedID: nil)
    private(set) var verified = false
    private(set) var isVerifying = false
    private(set) var message = "添加输入源后，切换到 RockType，再开始试打验证。"
    private(set) var registrationMessage: String?
    private(set) var isRegistering = false
    private(set) var isOpeningSettings = false
    private var registrationAttempted = false
    private var registeredThisSession = false
    private let enrollment: InputSourceEnrollment
    private var evidence: InputVerificationEvidence?
    private var attempt = UUID()
    private let generation: () async throws -> TranslationServiceClient.InputGeneration
    private let readSources: () -> InputSourceSnapshot
    private let disconnect: () -> Void

    init(client: TranslationServiceClient = TranslationServiceClient(),
         readSources: @escaping () -> InputSourceSnapshot = { .current() },
         enrollment: InputSourceEnrollment = .system) {
        self.enrollment = enrollment
        self.generation = { try await client.controllerInputGeneration() }
        self.readSources = readSources
        self.disconnect = { client.invalidate() }
        refresh()
    }

    init(readSources: @escaping () -> InputSourceSnapshot,
         disconnect: @escaping () -> Void = {},
         enrollment: InputSourceEnrollment = .system,
         generation: @escaping () async throws -> TranslationServiceClient.InputGeneration) {
        self.enrollment = enrollment
        self.generation = generation
        self.readSources = readSources
        self.disconnect = disconnect
        refresh()
    }

    func refresh() {
        snapshot = readSources()
        if let evidence, snapshot.selectedRoarkTID != evidence.sourceID {
            cancel()
            message = "输入源已切换，请选择 RockType 后重新开始验证。"
        }
    }

    func beginVerification() async {
        cancel()
        refresh()
        guard let sourceID = snapshot.selectedRoarkTID else {
            message = "请先在系统输入菜单中选中 RockType Pinyin 或 RockType Shuangpin。"
            return
        }
        let id = attempt
        isVerifying = true
        message = "正在连接验证服务…"
        do {
            let baseline = try await generation()
            guard attempt == id else { return }
            refresh()
            guard snapshot.selectedRoarkTID == sourceID else { cancel(); return }
            evidence = InputVerificationEvidence(sourceID: sourceID, baseline: baseline)
            message = "现在请在下方试打 nihao 并选字，然后点击“验证试打”。"
        } catch {
            guard attempt == id else { return }
            isVerifying = false
            message = "验证服务不可用，请确认主 App 与翻译服务已安装并重试。"
        }
    }

    func verify() async {
        refresh()
        guard let evidence else { return }
        let id = attempt
        do {
            let current = try await generation()
            guard attempt == id else { return }
            refresh()
            guard attempt == id else { return }
            if evidence.accepts(current, source: snapshot) {
                verified = true
                isVerifying = false
                message = "已确认 RockType 输入法处理了真实按键。"
            } else if current.connectionID != evidence.baseline.connectionID || current.value < evidence.baseline.value {
                cancel()
                message = "验证服务已重连，请重新开始试打验证。"
            } else {
                message = "尚未收到新的 RockType 按键记录，请继续试打后再验证。"
            }
        } catch {
            guard attempt == id else { return }
            cancel()
            message = "验证连接中断，请重新开始试打验证。"
        }
    }

    func cancel() {
        attempt = UUID()
        evidence = nil
        verified = false
        isVerifying = false
    }

    func stop() {
        cancel()
        disconnect()
    }

    /// Called only while the input-source step is visible. Registration does not add/select a source.
    func prepareRegistration() async {
        guard !isRegistering else { return }
        if enrollment.isRegistered() { registrationMessage = nil; return }
        isRegistering = true
        defer { isRegistering = false }
        if !registrationAttempted {
            registrationAttempted = true
            switch enrollment.register() {
            case .registered:
                registeredThisSession = true
            case .notInstalled:
                registrationMessage = "未找到 RockType 输入法安装文件，请先完成安装后重新打开主 App。"
                return
            case .failed:
                registrationMessage = "输入源注册失败，请重新安装后打开主 App。"
                return
            }
        }
        guard registeredThisSession else { return }
        registrationMessage = "正在向当前登录会话注册 RockType 输入源…"
        for _ in 0..<20 {
            guard !Task.isCancelled else { return }
            if enrollment.isRegistered() {
                registrationMessage = nil
                refresh()
                return
            }
            do { try await enrollment.pause() } catch { return }
        }
        registrationMessage = "系统尚未识别 RockType 输入源，请注销并重新登录后重试。"
    }

    func openKeyboardSettings() async {
        guard !isOpeningSettings, !isRegistering else { return }
        isOpeningSettings = true
        defer { isOpeningSettings = false }
        if await enrollment.openSettings(registeredThisSession) {
            registeredThisSession = false
        } else {
            registrationMessage = "无法刷新或打开键盘设置，请手动退出系统设置，再打开系统设置 → 键盘 → 输入法 → 编辑… → ＋ → 简体中文 → RockType。"
        }
    }
}

/// Narrow system boundary keeps registration, propagation and stale Settings handling testable.
@MainActor
struct InputSourceEnrollment {
    enum Registration { case registered, notInstalled, failed }
    var isRegistered: () -> Bool
    var register: () -> Registration
    var pause: () async throws -> Void
    var openSettings: (_ registeredThisSession: Bool) async -> Bool

    static var system: Self {
        Self(isRegistered: {
            let filter = [kTISPropertyBundleID as String: Identifiers.inputMethodBundleID] as CFDictionary
            let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as? [TISInputSource] ?? []
            let ids = Set(sources.compactMap { InputSourceSnapshot.string($0, kTISPropertyInputSourceID) })
            return InputSourceSnapshot.supportedIDs.isSubset(of: ids)
        }, register: {
            let locations = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods"),
                             URL(fileURLWithPath: "/Library/Input Methods", isDirectory: true)]
            guard let bundle = locations.map({ $0.appendingPathComponent("RockType Input.app", isDirectory: true) })
                .first(where: { Bundle(url: $0)?.bundleIdentifier == Identifiers.inputMethodBundleID }) else { return .notInstalled }
            return TISRegisterInputSource(bundle as CFURL) == noErr ? .registered : .failed
        }, pause: { try await Task.sleep(for: .milliseconds(100)) }, openSettings: { registeredThisSession in
            let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
            if registeredThisSession {
                let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
                // System Settings snapshots the addable list at launch. Never force-quit it.
                for app in apps where !app.isTerminated {
                    guard app.terminate() else { return false }
                }
                for _ in 0..<20 {
                    if apps.allSatisfy(\.isTerminated) { break }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
                }
                guard apps.allSatisfy(\.isTerminated) else { return false }
            }
            guard !Task.isCancelled else { return false }
            return NSWorkspace.shared.open(url)
        })
    }
}
