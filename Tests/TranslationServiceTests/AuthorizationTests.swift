import Foundation
import RoarkTCore
import RoarkTXPCProtocol
import Security
import Testing
@testable import RoarkTTranslationService

@Test func unsignedTestProcessCannotAuthenticateAsProduct() throws {
    var code: SecCode?
    #expect(SecCodeCopySelf([], &code) == errSecSuccess)
    let ownCode = try #require(code)
    #expect(TranslationClientCodeValidator.role(for: ownCode) == nil)
}

@Test @MainActor func mainAppCanPingButInputMethodIsDisconnected() {
    let coordinator = TranslationCoordinator()
    let app = TranslationXPCService(coordinator: coordinator, role: .mainApp)
    var version: String?
    app.ping { version = $0 }
    #expect(version == "2")
    var rejected = false
    let input = TranslationXPCService(coordinator: coordinator, role: .inputMethod,
                                     rejectConnection: { rejected = true })
    var replied = false
    input.ping { _ in replied = true }
    #expect(rejected)
    #expect(!replied)
}

@Test @MainActor func inputMethodCannotReadGenerationOrEndpoint() async {
    let coordinator = TranslationCoordinator()
    let listener = NSXPCListener.anonymous()
    coordinator.dictationEndpoints.register(listener.endpoint, owner: UUID())
    let service = TranslationXPCService(coordinator: coordinator, role: .inputMethod)
    let result = await withCheckedContinuation { continuation in
        service.controllerInputGeneration { generation, error in
            continuation.resume(returning: (generation, (error as NSError?)?.code))
        }
    }
    #expect(result.0 == 0)
    #expect(result.1 == CandidateTranslationFailure.unauthorized.rawValue)
    var endpoint: NSXPCListenerEndpoint?
    service.dictationEndpoint { endpoint = $0 }
    #expect(endpoint == nil)
}

@Test @MainActor func appCannotPublishEndpointOrRecordInputButCanReadBoth() async {
    let coordinator = TranslationCoordinator()
    let listener = NSXPCListener.anonymous()
    let service = TranslationXPCService(coordinator: coordinator, role: .mainApp)
    service.registerDictationEndpoint(listener.endpoint)
    service.recordControllerInput()
    let generation = await withCheckedContinuation { continuation in
        service.controllerInputGeneration { value, _ in continuation.resume(returning: value) }
    }
    #expect(generation == 0)
    let endpoint = await withCheckedContinuation { continuation in
        service.dictationEndpoint { continuation.resume(returning: $0) }
    }
    #expect(endpoint == nil)
    let registered = listener.endpoint
    coordinator.dictationEndpoints.register(registered, owner: UUID())
    let published = await withCheckedContinuation { continuation in
        service.dictationEndpoint { continuation.resume(returning: $0) }
    }
    #expect(published === registered)
}

@Test @MainActor func coordinatorDisconnectRemovesOwnedEndpoint() {
    let coordinator = TranslationCoordinator()
    let connection = UUID()
    let listener = NSXPCListener.anonymous()
    coordinator.dictationEndpoints.register(listener.endpoint, owner: connection)
    coordinator.removeConnection(connection)
    #expect(coordinator.dictationEndpoints.endpoint == nil)
}

@Test @MainActor func serviceExposesOnlyV2TranslationSelector() {
    let service = TranslationXPCService(coordinator: TranslationCoordinator(), role: .inputMethod)
    #expect(service.responds(to: NSSelectorFromString("translateCandidateWithSessionID:generation:request:withReply:")))
    #expect(!service.responds(to: NSSelectorFromString("translateWithSessionID:generation:rawInput:sourceText:withReply:")))
    _ = NSXPCInterface(with: RoarkTTranslationXPCProtocol.self)
    _ = NSXPCInterface(with: RoarkTDictationXPCProtocol.self)
}
