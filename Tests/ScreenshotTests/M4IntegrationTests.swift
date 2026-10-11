import XCTest
import AppKit
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class ScreenshotReplyRunner: OperationRunner {
    var requests: [OperationRequest] = []
    func start() {}
    func stop() {}
    func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        requests.append(request)
        let session = OperationSession(id: request.session.id, snapshot: request.session.snapshot,
            turns: request.session.turns + [.init(question: request.question ?? "", answer: "Synthetic answer")])
        return AsyncStream {
            $0.yield(.completed(.init(session: session, templateID: request.template.id,
                text: "Synthetic answer", engine: "synthetic")))
            $0.finish()
        }
    }
}

final class M4IntegrationTests: XCTestCase {
    @MainActor private func settle(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(condition())
    }

    @MainActor func testImageProbeRequiresSameConfigurationModelAndCredential() async {
        var settings = AIConnectionSettings()
        settings.baseURL = "https://synthetic.invalid"; settings.defaultModel = "synthetic-text"
        settings.visionModel = "synthetic-image"
        var secret: String? = "synthetic-key-a"
        let model = ShellConnectionModel()
        model.readKey = { _ in secret }; model.keyExists = { _ in secret != nil }
        model.runTests = { _, _ in Array(repeating: "可用", count: 4) }
        model.refresh(settings)
        XCTAssertFalse(model.imageCapabilityVerified(connection: settings, model: "synthetic-image"))
        model.test(); await settle { !model.testing }
        XCTAssertTrue(model.imageCapabilityVerified(connection: settings, model: "synthetic-image"))
        XCTAssertFalse(model.imageCapabilityVerified(connection: settings, model: "synthetic-text"))
        secret = "synthetic-key-b"
        XCTAssertFalse(model.imageCapabilityVerified(connection: settings, model: "synthetic-image"))
        secret = "synthetic-key-a"
        XCTAssertFalse(model.imageCapabilityVerified(connection: settings, model: "synthetic-image"))
        model.test(); await settle { !model.testing }
        XCTAssertTrue(model.imageCapabilityVerified(connection: settings, model: "synthetic-image"))
        settings.baseURL = "https://changed.invalid"
        XCTAssertFalse(model.imageCapabilityVerified(connection: settings, model: "synthetic-image"))
        model.test(); await settle { !model.testing }
        secret = nil
        XCTAssertFalse(model.imageCapabilityVerified(connection: settings, model: "synthetic-image"))
        model.cancel()
    }

    @MainActor func testChangedCredentialDuringProbeAndReadFailureFailClosed() async {
        var settings = AIConnectionSettings()
        settings.baseURL = "https://synthetic.invalid"; settings.defaultModel = "synthetic-image"
        settings.defaultModelSupportsImages = true
        var secret = "synthetic-key-a"
        var finish: CheckedContinuation<[String], Never>?
        let model = ShellConnectionModel()
        model.readKey = { _ in secret }; model.keyExists = { _ in true }
        model.runTests = { _, _ in await withCheckedContinuation { finish = $0 } }
        model.refresh(settings); model.test()
        await settle { finish != nil }
        secret = "synthetic-key-b"
        finish?.resume(returning: Array(repeating: "可用", count: 4))
        await settle { !model.testing }
        XCTAssertFalse(model.imageCapabilityVerified(connection: settings, model: settings.defaultModel))
        model.runTests = { _, _ in Array(repeating: "可用", count: 4) }
        model.test(); await settle { !model.testing }
        XCTAssertTrue(model.imageCapabilityVerified(connection: settings, model: settings.defaultModel))
        model.readKey = { _ in throw CocoaError(.fileReadNoPermission) }
        XCTAssertFalse(model.imageCapabilityVerified(connection: settings, model: settings.defaultModel))
    }

    @MainActor func testScreenshotResultsShareWindowFollowupsHistoryAndPrivacy() async throws {
        _ = NSApplication.shared
        var settings = AppSettings.defaults
        settings.privacy.keepRecentResultsInMemory = true
        let environment = OperationsEnvironment(); environment.start()
        let runner = ScreenshotReplyRunner()
        let operations = SelectionOperationsController(environment: environment, settings: { settings },
            aiConfigured: { true }, notice: { _ in }, readable: { true }, makeRunner: { runner })
        defer { operations.stop(); environment.stop() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        settings.ai.defaultModel = "synthetic-image"; settings.ai.defaultModelSupportsImages = true
        let preview = ScreenshotSession(image: try XCTUnwrap(context.makeImage()), origin: "synthetic",
            settings: { settings }, verified: { _, _ in true }, allowed: { true },
            sendImage: { _, _, _ in "Synthetic image explanation" })
        preview.performText = { operations.perform($0, source: nil, toolbarRect: nil) }
        preview.imageCompleted = { operations.presentCompleted($0, template: $1) }
        preview.text = "Corrected synthetic OCR"
        for id in ["translate", "summarize"] {
            preview.runText(templateID: id)
            await settle { operations.window?.state.phase == .done }
            XCTAssertEqual(operations.window?.state.session?.snapshot.text, preview.text)
            XCTAssertEqual(environment.recent.results.first?.templateID, id)
        }
        preview.prepareImage(); preview.confirmImage()
        await settle { environment.recent.results.first?.text == "Synthetic image explanation" }
        let result = try XCTUnwrap(environment.recent.results.first)
        XCTAssertEqual(operations.window?.state.answer, result.text)
        preview.close()
        XCTAssertEqual(environment.recent.results.count, 3, "Closing the preview must not erase shared history")
        operations.reopen(result)
        operations.window?.state.question = "Explain that answer"
        operations.window?.ask()
        await settle { operations.window?.state.phase == .done }
        XCTAssertEqual(runner.requests.last?.session.turns.last?.answer, "Synthetic image explanation")
        XCTAssertEqual(runner.requests.last?.question, "Explain that answer")
        settings.privacy.keepRecentResultsInMemory = false
        operations.settingsChanged()
        operations.presentCompleted(result, template: ScreenshotSession.imageTemplate)
        XCTAssertTrue(environment.recent.results.isEmpty)
        operations.clearCurrentContent()
        XCTAssertNil(operations.window)
        XCTAssertTrue(environment.recent.results.isEmpty)
    }
}
