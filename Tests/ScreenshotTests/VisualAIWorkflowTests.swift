import AppKit
import XCTest
import RoarkTCore
@testable import RoarkTApp

final class VisualAIWorkflowTests: XCTestCase {
    @MainActor private func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 24, height: 12))
        return try XCTUnwrap(context.makeImage())
    }
    private func settings() -> AppSettings {
        var value = AppSettings.defaults
        value.ai.baseURL = "https://synthetic.invalid/v1"; value.ai.name = "Synthetic"
        value.ai.visionModel = "synthetic-vision"
        return value
    }
    @MainActor private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
    @MainActor func testAllVisualActionsSendConfirmedEditedTextAndExactImage() async throws {
        let config = settings()
        var sent: [ScreenshotVisualAI.Request] = []
        var ocrCalls = 0
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { config }, verified: { _, _ in true },
            allowed: { true }, recognize: { _ in ocrCalls += 1; return "Local synthetic OCR" },
            sendVisual: { request, _, delta, permitted in
                XCTAssertTrue(permitted()); sent.append(request)
                await delta("Synthetic result"); return "Synthetic result"
            })
        defer { session.close() }
        session.prepareImage(action: .translate)
        await settle { session.confirmingImage }
        XCTAssertEqual(ocrCalls, 1); XCTAssertEqual(sent.count, 0)
        XCTAssertEqual(session.visual.request?.text, "Local synthetic OCR")
        session.cancel(); session.text = "Edited synthetic OCR"
        for action in [ScreenshotAIService.Action.translate, .summarize, .explain] {
            let count = sent.count
            session.prepareImage(action: action)
            XCTAssertTrue(session.confirmingImage); XCTAssertEqual(sent.count, count)
            let displayed = try XCTUnwrap(session.visual.request)
            XCTAssertEqual(displayed.text, session.text)
            session.confirmImage()
            await settle { session.visual.phase == .done }
            XCTAssertEqual(sent.last?.action, action)
            XCTAssertEqual(sent.last?.text, displayed.text)
            XCTAssertEqual(sent.last?.png, displayed.png)
            XCTAssertEqual(NSBitmapImageRep(data: displayed.png)?.pixelsWide, 24)
        }
        session.text = ""
        session.prepareImage(action: .translate); session.confirmImage()
        await settle { session.visual.phase == .done }
        XCTAssertEqual(sent.last?.text, ""); XCTAssertEqual(ocrCalls, 1)
    }
    @MainActor func testThinkingStreamingCancellationAndLateCompletion() async throws {
        let config = settings()
        var think: (@Sendable () async -> Void)?
        var delta: (@Sendable (String) async -> Void)?
        var finish: CheckedContinuation<String, any Error>?
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { config }, verified: { _, _ in true },
            allowed: { true }, sendVisual: { _, thinking, receive, _ in
                think = thinking; delta = receive
                return try await withCheckedThrowingContinuation { finish = $0 }
            })
        session.text = "Synthetic source"; session.prepareImage(); session.confirmImage()
        await settle { finish != nil }
        await think?(); XCTAssertEqual(session.visual.phase, .thinking); XCTAssertTrue(session.result.isEmpty)
        await delta?("Visible content"); XCTAssertEqual(session.visual.phase, .streaming)
        await think?(); XCTAssertEqual(session.visual.phase, .streaming)
        session.cancel(); await delta?(" late")
        finish?.resume(returning: "Late completed answer")
        await settle { !session.busy }
        XCTAssertEqual(session.visual.phase, .cancelled); XCTAssertTrue(session.result.isEmpty)
        session.close(); XCTAssertNil(session.visual.request)
    }
    @MainActor func testRememberOnlyAfterConfirmationAndRetryAlwaysReconfirms() async throws {
        var config = settings(), sent = 0
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { config }, verified: { _, _ in true },
            allowed: { true }, rememberImageConfirmation: { config.screenshot.skipImageAIConfirmation = $0 },
            sendVisual: { _, _, _, _ in sent += 1; throw AIClientError.timeout })
        defer { session.close() }
        session.text = "Synthetic source"; session.prepareImage(); session.cancel()
        XCTAssertNil(config.screenshot.skipImageAIConfirmation)
        session.prepareImage(); session.confirmImage(skipFuture: true)
        await settle { session.visual.phase == .failed }
        XCTAssertEqual(config.screenshot.skipImageAIConfirmation, true); XCTAssertEqual(sent, 1)
        session.retryImage(); XCTAssertTrue(session.confirmingImage); XCTAssertEqual(sent, 1)
        session.cancel(); session.prepareImage(action: .summarize)
        await settle { session.visual.phase == .failed }
        XCTAssertEqual(sent, 2)
        session.restoreImageConfirmation(); XCTAssertEqual(config.screenshot.skipImageAIConfirmation, false)
        session.prepareImage(); XCTAssertTrue(session.confirmingImage); XCTAssertEqual(sent, 2)
    }
    @MainActor func testEditsConfigurationAndProtectedInputInvalidatePendingAndRunningWork() async throws {
        var config = settings(), allowed = true, verified = true, sent = 0
        var finish: CheckedContinuation<String, any Error>?
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { config }, verified: { _, _ in verified },
            allowed: { allowed }, sendVisual: { _, _, _, _ in
                sent += 1; return try await withCheckedThrowingContinuation { finish = $0 }
            })
        defer { session.close() }
        session.text = "Synthetic source"; session.prepareImage()
        session.text = "Edited again"; session.confirmImage(); XCTAssertEqual(sent, 0)
        session.prepareImage(); config.ai.baseURL = "https://changed.invalid"; session.confirmImage()
        XCTAssertEqual(session.visual.phase, .failed); XCTAssertEqual(sent, 0)
        session.prepareImage(); session.confirmImage(); verified = false
        await settle { session.visual.phase == .failed }; XCTAssertEqual(sent, 0)
        verified = true; session.prepareImage(); session.confirmImage()
        await settle { finish != nil }; allowed = false
        await settle { session.visual.phase == .failed }
        finish?.resume(returning: "Must be discarded")
        XCTAssertTrue(session.result.isEmpty); XCTAssertNil(session.visual.request)
    }
    @MainActor func testFollowupOnlyExportsCompletedTextAndAllActionsHaveRetryGuard() async throws {
        let config = settings()
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { config }, verified: { _, _ in true },
            allowed: { true }, sendVisual: { _, _, _, _ in "Synthetic completed answer" })
        defer { session.close() }
        var exported: OperationResult?
        session.imageCompleted = { result, template in
            exported = result; XCTAssertNotNil(ScreenshotSession.imageTemplate(forID: template.id))
        }
        session.text = "Synthetic source not retained in followup"
        for action in [ScreenshotAIService.Action.translate, .summarize, .explain] {
            session.prepareImage(action: action); session.openImageFollowup(); XCTAssertNil(exported)
            session.confirmImage(); await settle { session.visual.phase == .done }
            session.openImageFollowup()
            let result = try XCTUnwrap(exported)
            XCTAssertFalse(result.session.snapshot.text.contains(session.text))
            XCTAssertEqual(result.session.turns.last?.answer, "Synthetic completed answer")
            XCTAssertEqual(result.templateID, ScreenshotVisualAI.template(action).id)
            exported = nil
        }
    }
    func testConfirmationPreferenceDefaultsAndRoundTripsWithoutResettingSettings() throws {
        var config = settings()
        let old = try JSONEncoder().encode(config)
        XCTAssertNil(try JSONDecoder().decode(AppSettings.self, from: old).screenshot.skipImageAIConfirmation)
        config.screenshot.skipImageAIConfirmation = true
        config.screenshot.roundedCorners = false
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored, config)
    }
}

extension VisualAIWorkflowTests {
    @MainActor func testPayloadLimitsBlockBeforeConfirmationAndSending() throws {
        let config = settings()
        var calls = 0
        let visual = ScreenshotVisualAI(settings: { config }, verified: { _, _ in true }, allowed: { true }, remember: { _ in },
            send: { _, _, _, _ in calls += 1; return "Unexpected" })
        visual.prepare(action: .translate, png: Data(count: 10 * 1024 * 1024 + 1), text: "synthetic")
        XCTAssertEqual(visual.phase, .failed); XCTAssertNil(visual.request)
        visual.prepare(action: .explain, png: Data([1]), text: String(repeating: "x", count: 32_769))
        XCTAssertEqual(visual.phase, .failed); XCTAssertNil(visual.request); XCTAssertEqual(calls, 0)
    }
    @MainActor func testPinTranslationAndOCRUseTheSharedPreview() async throws {
        let config = settings()
        let coordinator = ScreenshotCoordinator(captureFrames: { [] }, allowed: { true }, presentPreview: { _ in })
        coordinator.readSettings = { config }; coordinator.imageCapabilityVerified = { _, _ in true }
        coordinator.start(); defer { coordinator.stop() }
        PinnedImageController.shared.onAction(try image(), .translate)
        await settle { coordinator.session?.confirmingImage == true }
        XCTAssertEqual(coordinator.session?.visual.request?.action, .translate)
        XCTAssertTrue(coordinator.session?.ocrFinished == true)
        PinnedImageController.shared.onAction(try image(), .ocr)
        await settle { coordinator.session?.ocrFinished == true }
        XCTAssertEqual(coordinator.session?.visual.phase, .idle)
    }
}
