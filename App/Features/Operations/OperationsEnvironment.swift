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
    public func makeRunner(connectionID: String = "default", currentConnectionID: (@MainActor () -> String)? = nil) -> DefaultOperationRunner {
        let runner = DefaultOperationRunner(offline: TextTranslationXPCClient(),
            apiKey: { try Keychain().get(account: currentConnectionID?() ?? connectionID) ?? "" },
            isAllowed: { SecureInput.status() == .allowed },
            providerKey: { try Keychain().get(account: $0) ?? "" })
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
