import Foundation
import RoarkTXPCProtocol

@MainActor
final class DictationEndpointRegistry {
    private var owner: UUID?
    private(set) var endpoint: NSXPCListenerEndpoint?

    func register(_ endpoint: NSXPCListenerEndpoint, owner: UUID) {
        self.owner = owner
        self.endpoint = endpoint
    }

    func remove(owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        endpoint = nil
    }
}

extension TranslationXPCService {
    private final class EndpointReply: @unchecked Sendable {
        let call: (NSXPCListenerEndpoint?) -> Void
        init(_ call: @escaping (NSXPCListenerEndpoint?) -> Void) { self.call = call }
    }

    func registerDictationEndpoint(_ endpoint: NSXPCListenerEndpoint) {
        guard role == .inputMethod else { return }
        Task { @MainActor [coordinator, connectionID] in
            coordinator.dictationEndpoints.register(endpoint, owner: connectionID)
        }
    }

    func dictationEndpoint(reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
        guard role == .mainApp else { reply(nil); return }
        let reply = EndpointReply(reply)
        Task { @MainActor [coordinator] in reply.call(coordinator.dictationEndpoints.endpoint) }
    }
}
