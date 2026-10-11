import Foundation
import Testing
@testable import RoarkTCore

@Test(arguments: [("你好", "zh-en"), ("OpenAI你好", "zh-en"), ("𠀀", "zh-en"),
                  ("café", "en-zh"), ("cafe\u{301}", "en-zh"), ("don’t", "en-zh")])
func candidatePayloadRoundTrips(_ source: String, _ direction: String) throws {
    let request = try CandidateTranslationRequest(rawInput: "nihao", sourceText: source,
                                                  identity: "0:5:0", scope: .whole)
    #expect(try CandidateTranslationRequest(payload: request.payload) == request)
    #expect(request.direction.rawValue == direction)
    #expect(request.accepts(source: source, direction: direction))
    #expect(!request.accepts(source: "different", direction: direction))
}

@Test(arguments: [("version", "1"), ("scope", "unknown"), ("direction", "en-zh"),
                  ("identity", "0:6:0"), ("identity", "0:0:0"), ("identity", "-1:3:0"),
                  ("identity", "0:3:-1"), ("identity", "0:3:0:1"), ("identity", "x:3:0"),
                  ("rawInput", ""), ("sourceText", ""), ("sourceText", "привет"),
                  ("sourceText", "!? 123"), ("extra", "value")])
func invalidCandidatePayloadIsRejected(_ key: String, _ value: String) throws {
    let request = try CandidateTranslationRequest(rawInput: "nihao", sourceText: "你好",
                                                  identity: "0:5:0", scope: .whole)
    var payload = request.payload
    payload[key] = value
    #expect(throws: CandidateTranslationRequest.ValidationError.self) {
        try CandidateTranslationRequest(payload: payload)
    }
}

@Test func candidateLengthLimitCountsUTF8Bytes() throws {
    let valid = try CandidateTranslationRequest(rawInput: String(repeating: "a", count: 4096),
        sourceText: "你好", identity: "0:4096:0", scope: .whole)
    var payload = valid.payload
    payload["rawInput"] = String(repeating: "你", count: 1366)
    #expect(throws: CandidateTranslationRequest.ValidationError.self) {
        try CandidateTranslationRequest(payload: payload)
    }
    payload = valid.payload
    payload["sourceText"] = String(repeating: "你", count: 1366)
    #expect(throws: CandidateTranslationRequest.ValidationError.self) {
        try CandidateTranslationRequest(payload: payload)
    }
}

@Test func staticFallbackMatchesSelectedSourceOnly() throws {
    let greeting = try CandidateTranslationRequest(rawInput: "nihao", sourceText: "你好",
        identity: "0:5:0", scope: .whole)
    let other = try CandidateTranslationRequest(rawInput: "nihao", sourceText: "拟好",
        identity: "0:5:1", scope: .whole)
    #expect(greeting.staticTranslation == "hello")
    #expect(other.staticTranslation == nil)
    #expect(CandidateTranslationFailure.errorDomain == Identifiers.translationServiceName)
    #expect(CandidateTranslationFailure.from(CancellationError()) == .cancelled)
}
