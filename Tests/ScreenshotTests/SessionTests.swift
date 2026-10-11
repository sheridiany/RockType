import XCTest
import AppKit
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class RecordingRunner: OperationRunner {
    var requests: [OperationRequest] = []
    var cancelled = 0
    func start() {}
    func stop() { cancel() }
    func cancel() { cancelled += 1 }
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        requests.append(request)
        return AsyncStream { $0.yield(.delta("Synthetic reply")); $0.finish() }
    }
}
final class SessionTests: XCTestCase {
    private func image() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(ctx.makeImage())
    }
    @MainActor func testTranslationUsesEditedOCRAndSettings() async throws {
        var settings = AppSettings.defaults
        settings.translation.targetLanguage = "fr"
        let runner = RecordingRunner()
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { settings }, verified: { _, _ in false },
            runner: runner, allowed: { true }, recognize: { _ in "Synthetic OCR" })
        session.runOCR()
        for _ in 0..<100 where !session.ocrFinished { await Task.yield() }
        XCTAssertTrue(session.ocrFinished)
        session.text = "Corrected synthetic text"
        session.runText(templateID: "translate")
        XCTAssertEqual(runner.requests.first?.session.snapshot.text, "Corrected synthetic text")
        XCTAssertEqual(runner.requests.first?.settings.translation.targetLanguage, "fr")
        session.close()
    }
    @MainActor func testImageRequiresVerifiedCapabilityAndExplicitConfirmation() async throws {
        var settings = AppSettings.defaults
        settings.ai.defaultModel = "synthetic-vision"; settings.ai.defaultModelSupportsImages = true
        var verified = false, sent = 0
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { settings }, verified: { _, _ in verified },
            runner: RecordingRunner(), allowed: { true }, sendImage: { _, _, bytes in
                XCTAssertNotNil(NSBitmapImageRep(data: bytes)); sent += 1; return "Synthetic reply"
            })
        session.prepareImage(); session.confirmImage()
        XCTAssertFalse(session.confirmingImage); XCTAssertEqual(sent, 0)
        verified = true; session.prepareImage()
        XCTAssertTrue(session.confirmingImage); XCTAssertEqual(sent, 0)
        settings.ai.baseURL = "https://changed.invalid"
        session.confirmImage(); XCTAssertEqual(sent, 0)
        session.prepareImage(); session.confirmImage()
        for _ in 0..<100 where session.busy { await Task.yield() }
        XCTAssertEqual(sent, 1); XCTAssertEqual(session.result, "Synthetic reply")
        session.close()
    }
    @MainActor func testCloseDropsLateOCRAndReleasesContent() async throws {
        var completion: CheckedContinuation<String, any Error>?
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { .defaults }, verified: { _, _ in false },
            runner: RecordingRunner(), allowed: { true }, recognize: { _ in
                try await withCheckedThrowingContinuation { completion = $0 }
            })
        session.runOCR()
        for _ in 0..<100 where completion == nil { await Task.yield() }
        session.close(); completion?.resume(returning: "Late synthetic result")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(session.image); XCTAssertEqual(session.text, ""); XCTAssertFalse(session.busy)
    }
    @MainActor func testProtectedInputMakesNoOCRTextOrImageRequest() async throws {
        var calls = 0
        let runner = RecordingRunner()
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { .defaults }, verified: { _, _ in true },
            runner: runner, allowed: { false }, recognize: { _ in calls += 1; return "" },
            sendImage: { _, _, _ in calls += 1; return "" })
        session.text = "Synthetic text"
        session.runOCR(); session.runText(templateID: "translate"); session.prepareImage(); session.confirmImage()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(calls, 0); XCTAssertTrue(runner.requests.isEmpty)
        session.close()
    }
}
