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

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
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
    private(set) var message = "添加输入源后，切换到 RoarkT，再开始试打验证。"
    private var evidence: InputVerificationEvidence?
    private var attempt = UUID()
    private let generation: () async throws -> TranslationServiceClient.InputGeneration
    private let readSources: () -> InputSourceSnapshot
    private let disconnect: () -> Void

    init(client: TranslationServiceClient = TranslationServiceClient(),
         readSources: @escaping () -> InputSourceSnapshot = { .current() }) {
        self.generation = { try await client.controllerInputGeneration() }
        self.readSources = readSources
        self.disconnect = { client.invalidate() }
        refresh()
    }

    init(readSources: @escaping () -> InputSourceSnapshot,
         disconnect: @escaping () -> Void = {},
         generation: @escaping () async throws -> TranslationServiceClient.InputGeneration) {
        self.generation = generation
        self.readSources = readSources
        self.disconnect = disconnect
        refresh()
    }

    func refresh() {
        snapshot = readSources()
        if let evidence, snapshot.selectedRoarkTID != evidence.sourceID {
            cancel()
            message = "输入源已切换，请选择 RoarkT 后重新开始验证。"
        }
    }

    func beginVerification() async {
        cancel()
        refresh()
        guard let sourceID = snapshot.selectedRoarkTID else {
            message = "请先在系统输入菜单中选中 RoarkT（全拼或小鹤双拼）。"
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
                message = "已确认 RoarkT 输入法处理了真实按键。"
            } else if current.connectionID != evidence.baseline.connectionID || current.value < evidence.baseline.value {
                cancel()
                message = "验证服务已重连，请重新开始试打验证。"
            } else {
                message = "尚未收到新的 RoarkT 按键记录，请继续试打后再验证。"
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

    func openKeyboardSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        if !NSWorkspace.shared.open(url) { message = "无法打开键盘设置，请手动打开系统设置 → 键盘 → 文本输入。" }
    }
}
