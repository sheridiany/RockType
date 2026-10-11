import Foundation
import Observation
import RoarkTCore
import RoarkTPlatform

/// Claude integration: retain one instance, start after SettingsStore is ready,
/// stop from applicationWillTerminate. No AppDelegate ownership in this task.
@MainActor @Observable final class InputAIController {
    private(set) var message = "输入法 AI 未启用。"
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let transport: any InputAIConfiguring
    @ObservationIgnored private let secret: (String) throws -> String?
    @ObservationIgnored private let beginKeyMonitoring: () -> Bool
    @ObservationIgnored private let endKeyMonitoring: () -> Void
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var running = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var connectionRevision = 0
    @ObservationIgnored private var lastSent: [String: String]?
    @ObservationIgnored private var sending: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var keyFallback: Task<Void, Never>?

    init(store: SettingsStore = .shared, transport: (any InputAIConfiguring)? = nil,
         secret: @escaping (String) throws -> String? = { try Keychain().get(account: $0) },
         beginKeyMonitoring: (() -> Bool)? = nil, endKeyMonitoring: (() -> Void)? = nil) {
        self.store = store; self.transport = transport ?? InputAIConfigurationClient(); self.secret = secret
        let monitor = InputAIKeychainMonitor()
        self.beginKeyMonitoring = beginKeyMonitoring ?? { monitor.start() }
        self.endKeyMonitoring = endKeyMonitoring ?? { monitor.stop() }
    }

    func start() {
        guard !running else { return }
        running = true
        transport.onDisconnect = { [weak self] in
            guard let self, self.running else { return }
            self.connectionRevision += 1; self.lastSent = nil; self.scheduleRetry()
        }
        observers.append(NotificationCenter.default.addObserver(forName: SettingsStore.didChange, object: nil, queue: .main) { [weak self] note in
            let changedStore = note.object as? SettingsStore
            MainActor.assumeIsolated {
                guard let self, changedStore === self.store else { return }
                self.refresh()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: InputAIKeychainMonitor.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        if !beginKeyMonitoring() {
            // Keychain callbacks are legacy macOS API. If registration fails, still
            // revoke deleted/replaced credentials with bounded polling.
            keyFallback = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    self?.refresh()
                }
            }
        }
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false; revision += 1
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        endKeyMonitoring(); keyFallback?.cancel(); keyFallback = nil
        retry?.cancel(); retry = nil; sending?.cancel(); sending = nil
        lastSent = nil; transport.onDisconnect = nil; transport.clearAndInvalidate()
        message = "输入法 AI 已停止。"
    }

    /// Also available to an integration host after an explicit credential edit.
    func refresh() {
        guard running else { return }
        revision += 1
        retry?.cancel(); retry = nil
        guard sending == nil else { return }
        sending = Task { [weak self] in await self?.synchronize() }
    }

    private func synchronize() async {
        while running, !Task.isCancelled {
            let current = revision
            let connection = connectionRevision
            let config = configuration()
            if config != lastSent {
                do {
                    try await transport.configure(config)
                    guard running, !Task.isCancelled else { return }
                    // A reply queued just before a disconnect must not make the
                    // next connection appear configured. Re-send the latest snapshot.
                    guard connection == connectionRevision else { continue }
                    lastSent = config
                    message = config.isEmpty ? "输入法 AI 已关闭或尚未配置。" : "输入法 AI 配置已同步。"
                } catch {
                    guard running, !Task.isCancelled else { return }
                    transport.invalidate(); lastSent = nil
                    message = "输入法 AI 服务暂不可用，将自动重试。"
                    sending = nil; scheduleRetry(); return
                }
            }
            if current == revision { sending = nil; return }
        }
    }

    private func scheduleRetry() {
        guard running, retry == nil else { return }
        retry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.retry = nil; self?.refresh()
        }
    }

    private func configuration() -> [String: String] {
        let settings = store.settings
        let input = settings.input.inputAI ?? InputAISettings()
        guard input.enabled, input.timeout.isFinite, (0.1...120).contains(input.timeout),
              let url = URLComponents(string: settings.ai.baseURL), AIClient.isAllowedEndpoint(url),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !settings.ai.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let polish = settings.templates.first(where: { $0.id == "polish" && $0.input == .text }),
              let translate = settings.templates.first(where: { $0.id == "translate" && $0.input == .text }),
              !polish.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !translate.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let key = try? secret(settings.ai.id), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !key.contains("\n"), !key.contains("\r") else { return [:] }
        let values = ["baseURL": settings.ai.baseURL, "model": settings.ai.defaultModel, "apiKey": key,
                      "timeout": String(input.timeout), "polishPrompt": OperationPrompts.resolved(polish),
                      "rewritePrompt": OperationPrompts.resolved(polish) + "\n请改写措辞与句式，保留原意，仅输出改写结果。",
                      "translatePrompt": OperationPrompts.resolved(translate)]
        guard values.values.allSatisfy({ $0.utf8.count <= 32_768 }) else { return [:] }
        return values
    }

    isolated deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        endKeyMonitoring(); keyFallback?.cancel(); retry?.cancel(); sending?.cancel()
        transport.onDisconnect = nil; transport.invalidate()
    }
}
