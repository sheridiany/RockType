import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor @Test func imageVerificationBelongsToProfileAndRevokesChangedCredentials() async {
    let model = ShellConnectionModel()
    var secrets = ["one": "synthetic-one", "two": "synthetic-two"]
    model.readKey = { secrets[$0] }; model.keyExists = { secrets[$0] != nil }
    model.runTests = { _, _ in Array(repeating: "可用", count: 5) }
    var one = AIConnectionSettings()
    one.id = "one"; one.baseURL = "https://one.invalid"; one.defaultModel = "image"
    one.defaultModelSupportsImages = true; one.fallbackModel = "image-backup"
    var two = one; two.id = "two"; two.baseURL = "https://two.invalid"
    func probe(_ config: AIConnectionSettings) async {
        model.refresh(config); model.test()
        let deadline = ContinuousClock.now + .seconds(2)
        while model.testing, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!model.testing)
    }
    await probe(one); await probe(two)
    #expect(model.imageCapabilityVerified(connection: one, model: "image"))
    #expect(model.imageCapabilityVerified(connection: one, model: "image-backup"))
    #expect(model.imageCapabilityVerified(connection: two, model: "image"))
    secrets["one"] = "replacement"
    #expect(!model.imageCapabilityVerified(connection: one, model: "image"))
    secrets["one"] = "synthetic-one"
    #expect(!model.imageCapabilityVerified(connection: one, model: "image"))
    #expect(model.imageCapabilityVerified(connection: two, model: "image"))
    model.cancel()
}
