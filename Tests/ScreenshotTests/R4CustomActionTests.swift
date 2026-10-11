import AppKit
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor @Test func customImageActionRequiresConfirmationAndInvalidatesEditedDefinition() async throws {
    var settings = AppSettings.defaults
    settings.ai.defaultModel = "synthetic-default"
    var template = OperationTemplate(name: "Synthetic image action", icon: "photo", prompt: "Synthetic custom instruction", input: .image, model: "synthetic-custom-image")
    template.showInScreenshot = true; settings.templates.append(template)
    var sent: [ScreenshotVisualAI.Request] = []
    let workflow = ScreenshotVisualAI(settings: { settings }, verified: { _, model in model == "synthetic-custom-image" }, allowed: { true }, remember: { _ in }, send: { request, _, _, permitted in
        #expect(permitted()); sent.append(request); return "Synthetic answer"
    })
    workflow.prepare(action: .explain, png: Data([1]), text: "Corrected synthetic text", template: template)
    #expect(workflow.phase == .confirming && sent.isEmpty)
    #expect(workflow.request?.model == template.model)
    settings.templates[settings.templates.count - 1].prompt = "Changed instruction"
    workflow.confirm()
    #expect(workflow.phase == .failed && sent.isEmpty)
    settings.templates[settings.templates.count - 1] = template
    workflow.prepare(action: .explain, png: Data([1]), text: "Corrected synthetic text", template: template)
    workflow.confirm()
    for _ in 0..<100 where workflow.phase != .done { try await Task.sleep(for: .milliseconds(5)) }
    #expect(workflow.phase == .done)
    #expect(sent.first?.template?.prompt == template.prompt)
    let result = try #require(workflow.completedResult(origin: "Synthetic"))
    #expect(result.1.name == template.name && result.1.input == .text)
    #expect(ScreenshotSession.imageTemplate(forID: result.0.templateID) != nil)
    workflow.clear()
}

@MainActor @Test func screenshotTextActionUsesEditedOCRAndCurrentTemplate() throws {
    var settings = AppSettings.defaults
    var template = OperationTemplate(name: "Synthetic text action", icon: "sparkles", prompt: "Synthetic custom instruction", model: "synthetic-model")
    template.showInScreenshot = true; settings.templates.append(template)
    let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let session = ScreenshotSession(image: try #require(context.makeImage()), origin: "Synthetic", settings: { settings }, verified: { _, _ in false }, allowed: { true })
    defer { session.close() }
    var requests: [OperationRequest] = []
    session.performText = { requests.append($0) }
    session.text = "User-corrected synthetic text"
    session.runTemplate(template.id)
    #expect(requests.count == 1)
    #expect(requests.first?.template == template)
    #expect(requests.first?.session.snapshot.text == "User-corrected synthetic text")
    #expect(session.screenshotTemplates.map(\.id) == [template.id])
    settings.templates[settings.templates.count - 1].showInScreenshot = false
    #expect(session.screenshotTemplates.isEmpty)
}
