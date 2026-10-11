import Foundation
import Testing
@testable import RoarkTTranslationService

@Test @MainActor func oldPublisherDisconnectCannotRemoveNewVoiceEndpoint() {
    let registry = DictationEndpointRegistry()
    let oldOwner = UUID()
    let newOwner = UUID()
    let oldListener = NSXPCListener.anonymous()
    let newListener = NSXPCListener.anonymous()
    let newest = newListener.endpoint
    registry.register(oldListener.endpoint, owner: oldOwner)
    registry.register(newest, owner: newOwner)
    registry.remove(owner: oldOwner)
    #expect(registry.endpoint === newest)
    registry.remove(owner: newOwner)
    #expect(registry.endpoint == nil)
}
