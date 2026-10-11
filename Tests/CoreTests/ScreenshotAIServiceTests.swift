import Foundation
import Testing
@testable import RoarkTCore

@MainActor private final class ScreenshotProbeState {
    var allowed = true
    var ocrCalls = 0
}

@MainActor @Test func screenshotCombinesCorrectedOCRAndImageAndProtectsBeforeNetwork() async throws {
    let sse = Data("data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Image answer\"}}]}\n\ndata: [DONE]\n\n".utf8)
    let (client, host, session) = makeClient(.init(chunks: [sse]), images: true)
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let state = ScreenshotProbeState()
    let service = ScreenshotAIService(client: client, recognize: { _ in
        await MainActor.run { state.ocrCalls += 1 }
        return "Synthetic OCR"
    }, isAllowed: { state.allowed })
    let data = Data([0])
    #expect(try await service.run(action: .translate, png: data, correctedText: "Corrected synthetic OCR",
        model: "test-model", imageCapabilityVerified: true, apiKey: "synthetic-key") == "Image answer")
    #expect(state.ocrCalls == 0)
    let request = try #require(AIStub.request(host))
    let input = try #require(request.httpBodyStream)
    input.open(); defer { input.close() }
    var body = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
    while input.hasBytesAvailable {
        let count = input.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        body.append(contentsOf: buffer.prefix(count))
    }
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(json["messages"] as? [[String: Any]])
    let content = try #require(messages.first?["content"] as? [[String: Any]])
    #expect((content.first?["text"] as? String)?.contains("Corrected synthetic OCR") == true)
    #expect(content.last?["type"] as? String == "image_url")
    _ = try await service.run(action: .summarize, png: data, model: "test-model",
        imageCapabilityVerified: true, apiKey: "synthetic-key")
    #expect(state.ocrCalls == 1)
    state.allowed = false
    await #expect(throws: OperationFailure.protectedInput) {
        try await service.run(action: .explain, png: data, model: "test-model", imageCapabilityVerified: true, apiKey: "synthetic-key")
    }
    #expect(AIStub.count(host) == 2 && state.ocrCalls == 1)
    state.allowed = true
    await #expect(throws: OperationFailure.unsupportedInput) {
        try await service.run(action: .explain, png: data, model: "test-model", imageCapabilityVerified: false, apiKey: "synthetic-key")
    }
    #expect(AIStub.count(host) == 2)
}

@MainActor @Test func screenshotProtectionCancelsWhileModelIsSilent() async throws {
    let (client, host, session) = makeClient(.init(hang: true), images: true)
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let state = ScreenshotProbeState()
    let service = ScreenshotAIService(client: client, recognize: { _ in "Synthetic OCR" }, isAllowed: { state.allowed })
    let task = Task { try await service.run(action: .explain, png: Data([0]), model: "test-model",
        imageCapabilityVerified: true, apiKey: "synthetic-key") }
    for _ in 0..<100 where AIStub.count(host) == 0 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(AIStub.count(host) == 1)
    state.allowed = false
    await #expect(throws: OperationFailure.protectedInput) { try await task.value }
    for _ in 0..<100 where !AIStub.wasStopped(host) { try await Task.sleep(for: .milliseconds(5)) }
    #expect(AIStub.wasStopped(host))
}

