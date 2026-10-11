import AppKit
import XCTest
import RoarkTCore
import RoarkTPlatform
@testable import RoarkTApp

@MainActor private final class BatchOffline: TextTranslationClient {
    var texts: [String] = []
    var fails = false
    func translate(sessionID: UUID, generation: UInt64, text: String, target: String) async throws -> String {
        texts.append(text)
        if fails { throw OperationFailure.unavailable }
        return "[[RT:0]]\n你好，世界\n[[RT:1]]\n准备继续\n[[RT:END]]"
    }
    func cancel(sessionID: UUID, throughGeneration: UInt64) {}
    func stop() {}
}
private actor BatchAI {
    var prompts: [String] = []
    func reply(_ prompt: String) -> String { prompts.append(prompt); return "[[RT:0]]\n你好，世界\n[[RT:1]]\n准备继续\n[[RT:END]]" }
}
final class OverlayRoutingTests: XCTestCase {
    @MainActor func testWholeImageUsesOfflineOnceThenExistingOptionalAIRoute() async throws {
        let offline = BatchOffline(), ai = BatchAI()
        let runner = DefaultOperationRunner(offline: offline, apiKey: { "synthetic" }, isAllowed: { true },
            streamAI: { _, prompt, _, _, _ in await ai.reply(prompt) })
        let overlay = ScreenshotOverlayTranslation(runner: runner, allowed: { true })
        let image = try OverlayTranslationTests.image()
        var config = AppSettings.defaults
        overlay.run(image: image, lines: OverlayTranslationTests.lines, settings: config)
        await OverlayTranslationTests.settle { overlay.phase == .done }
        XCTAssertEqual(offline.texts.count, 1); XCTAssertEqual(overlay.engine, "Apple Translation")
        let initialPrompts = await ai.prompts; XCTAssertTrue(initialPrompts.isEmpty)
        offline.fails = true
        overlay.run(image: image, lines: OverlayTranslationTests.lines, settings: config)
        await OverlayTranslationTests.settle { overlay.phase == .done }
        XCTAssertEqual(offline.texts.count, 2)
        let fallback = await ai.prompts; XCTAssertEqual(fallback.count, 1)
        for line in OverlayTranslationTests.lines { XCTAssertTrue(fallback[0].contains(line.text)) }
        config.translation.engine = .ai
        overlay.run(image: image, lines: OverlayTranslationTests.lines, settings: config)
        await OverlayTranslationTests.settle { overlay.phase == .done }
        XCTAssertEqual(offline.texts.count, 2)
        let explicit = await ai.prompts; XCTAssertEqual(explicit.count, 2)
        overlay.clear()
    }
    @MainActor func testSessionUsesRealOCRGeometryAndExportsSelectedImageThenDropsItOnEdit() async throws {
        let runner = OverlayTestRunner()
        let session = ScreenshotSession(image: try OverlayTranslationTests.image(), origin: "synthetic", settings: { .defaults }, verified: { _, _ in false },
            allowed: { true }, overlayRunner: runner, scanCodes: { _ in [] })
        defer { session.close() }
        session.translateImage()
        await OverlayTranslationTests.settle { !runner.requests.isEmpty }
        XCTAssertTrue(session.ocrFinished); XCTAssertFalse(session.ocrLines.isEmpty)
        XCTAssertEqual(runner.requests.count, 1); XCTAssertEqual(session.previewMode, .overlay)
        runner.complete(session.ocrLines.enumerated().map { "[[RT:\($0.offset)]]\n合成译文" }.joined(separator: "\n") + "\n[[RT:END]]")
        await OverlayTranslationTests.settle { session.overlay.phase == .done }
        let original = try XCTUnwrap(session.png())
        session.showTranslatedImage = true
        XCTAssertTrue(session.displayedImage === session.overlay.image)
        XCTAssertNotEqual(session.png(displayed: true), original)
        XCTAssertEqual(session.png(), original) // AI still receives the original, never a translated derivative.
        session.showTranslatedImage = false; XCTAssertEqual(session.png(displayed: true), original)
        session.text = "Edited transcript"
        XCTAssertNil(session.overlay.image); XCTAssertFalse(session.showTranslatedImage)
    }
}
