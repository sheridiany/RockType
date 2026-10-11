import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

private actor PolishTransport {
    var calls = 0
    var failure = false
    func fail() { failure = true }
    func send() throws -> String {
        calls += 1
        if failure { throw URLError(.timedOut) }
        return "合成润色结果。"
    }
}

@MainActor @Test func voicePolishRequiresOptInAndCredentialsAndFallsBackOnFailure() async {
    var settings = AppSettings()
    settings.ai.baseURL = "https://example.invalid/v1"
    settings.ai.defaultModel = "synthetic-model"
    var allowed = true
    var key: String? = "synthetic-test-key"
    let transport = PolishTransport()
    let polisher = VoicePolisher(settings: { settings }, allowed: { allowed }, secret: { _ in key },
                                complete: { _, _, _ in try await transport.send() })
    let original = "合成原文"
    #expect(await polisher.polish(original) == original)
    #expect(await transport.calls == 0)
    settings.voice.polishWithAI = true; key = nil
    #expect(await polisher.polish(original) == original)
    #expect(await transport.calls == 0)
    key = "synthetic-test-key"; allowed = false
    #expect(await polisher.polish(original) == original)
    #expect(await transport.calls == 0)
    allowed = true
    #expect(await polisher.polish(original) == "合成润色结果。")
    await transport.fail()
    #expect(await polisher.polish(original) == original)
    #expect(await transport.calls == 2)
}

@MainActor @Test func voicePolishRejectsEmptyMultilineAndOversizedOutput() async {
    var settings = AppSettings()
    settings.voice.polishWithAI = true
    settings.ai.baseURL = "https://example.invalid/v1"; settings.ai.defaultModel = "synthetic-model"
    for result in ["", "段一\n段二", String(repeating: "a", count: 32_769)] {
        let polisher = VoicePolisher(settings: { settings }, allowed: { true }, secret: { _ in "synthetic-test-key" },
                                    complete: { _, _, _ in result })
        #expect(await polisher.polish("合成原文") == "合成原文")
    }
}
