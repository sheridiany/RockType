import AppKit
import RoarkTCore
import RoarkTPlatform

/// Composition entry point for AppDelegate integration. Create one runner per result window.
@MainActor
public final class OperationsEnvironment {
    public let recent = InMemoryRecentResults()
    private struct WeakRunner { weak var value: DefaultOperationRunner? }
    private var runners: [WeakRunner] = []
    public init() {}
    public func start() { recent.start() }
    public func stop() { clearCurrentContent(); recent.stop() }
    public func clearCurrentContent() {
        runners.forEach { $0.value?.stop() }
        runners.removeAll { $0.value == nil }
        recent.clear()
    }
    public func makeRunner(connectionID: String = "default") -> DefaultOperationRunner {
        let runner = DefaultOperationRunner(offline: TextTranslationXPCClient(), recent: recent,
            apiKey: { try Keychain().get(account: connectionID) ?? "" },
            isAllowed: { SecureInput.status() == .allowed })
        runners.removeAll { $0.value == nil }; runners.append(WeakRunner(value: runner))
        return runner
    }
    /// Search is an explicit local action; it never invokes AI.
    @discardableResult
    public func search(_ query: String, settings: SelectionSettings) throws -> Bool {
        guard SecureInput.status() == .allowed else { throw OperationFailure.protectedInput }
        return NSWorkspace.shared.open(try SearchURL.make(query: query, engine: settings.searchEngine))
    }
}
