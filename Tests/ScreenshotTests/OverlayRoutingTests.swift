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
        config.ai.baseURL = "https://synthetic.invalid/v1"
        config.ai.defaultModel = "synthetic-translation"
        overlay.run(image: image, lines: OverlayTranslationTests.lines, settings: config)
        await OverlayTranslationTests.settle { overlay.phase == .done }
        XCTAssertEqual(offline.texts.count, 1); XCTAssertEqual(overlay.engine, "Apple Translation")
        let initialPrompts = await ai.prompts; XCTAssertTrue(initialPrompts.isEmpty)
        offline.fails = true
        overlay.run(image: image, lines: OverlayTranslationTests.lines, settings: config)
        await OverlayTranslationTests.settle { overlay.phase == .done }
        XCTAssertEqual(offline.texts.count, 2)
        let fallback = await ai.prompts; XCTAssertEqual(fallback.count, 1)
        let fallbackPrompt = try XCTUnwrap(fallback.first)
        for line in OverlayTranslationTests.lines { XCTAssertTrue(fallbackPrompt.contains(line.text)) }
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


private actor OverlayProviderCalls {
    struct Call: Equatable, Sendable {
        let provider: String
        let model: String
        let key: String
    }
    private(set) var values: [Call] = []
    func record(_ provider: String, _ model: String, _ key: String) { values.append(.init(provider: provider, model: model, key: key)) }
}
extension OverlayRoutingTests {
    private func providerSettings() -> AppSettings {
        var settings = AppSettings.defaults
        settings.ai.id = "default-provider"; settings.ai.defaultModel = "default-model"
        settings.ai.baseURL = "https://default.invalid/v1"
        var translation = AIConnectionSettings()
        translation.id = "translation-provider"; translation.name = "Synthetic translation"
        translation.baseURL = "https://translation.invalid/v1"; translation.defaultModel = "provider-default"
        translation.fallbackModel = "translation-backup"
        settings.aiProviders = [translation]
        settings.aiTaskRoutes = [AITask.translation.rawValue: .init(providerID: translation.id, model: "translation-task")]
        return settings
    }
    @MainActor func testProductionOverlayAssemblyUsesTranslationProviderCredentialAndBackup() async throws {
        let config = providerSettings(), calls = OverlayProviderCalls(), offline = BatchOffline()
        offline.fails = true
        var accounts: [String] = []
        let runner = ScreenshotSession.makeOverlayRunner(allowed: { true }, offline: offline,
            providerKey: { id in accounts.append(id); return "synthetic-" + id }, streamAI: { connection, prompt, key, model, _ in
                await calls.record(connection.id, model, key)
                guard key == "synthetic-translation-provider" else { throw AIClientError.unauthorized }
                guard prompt.contains("Hello world"), prompt.contains("Ready to continue") else { throw AIClientError.decoding }
                if model == "translation-task" { throw AIClientError.server }
                return "[[RT:0]]\n你好，世界\n[[RT:1]]\n准备继续\n[[RT:END]]"
            })
        let overlay = ScreenshotOverlayTranslation(runner: runner, allowed: { true })
        defer { overlay.clear() }
        overlay.run(image: try OverlayTranslationTests.image(), lines: OverlayTranslationTests.lines, settings: config)
        await OverlayTranslationTests.settle { overlay.phase != .running }
        XCTAssertEqual(overlay.phase, .done); XCTAssertNotNil(overlay.image)
        XCTAssertEqual(offline.texts.count, 1)
        XCTAssertEqual(accounts, ["translation-provider"])
        let sent = await calls.values
        XCTAssertEqual(sent, [
            .init(provider: "translation-provider", model: "translation-task", key: "synthetic-translation-provider"),
            .init(provider: "translation-provider", model: "translation-backup", key: "synthetic-translation-provider")])
        XCTAssertEqual(overlay.engine, "Synthetic translation · translation-backup · 备用模型")
    }
    @MainActor func testUnavailableTranslationProviderFailsBeforeCredentialReadOrTransport() async throws {
        for missing in [false, true] {
            var config = providerSettings(); config.translation.engine = .ai
            if missing { config.aiProviders = [] }
            else { config = .defaults; config.translation.engine = .ai }
            var reads = 0
            let calls = OverlayProviderCalls()
            let runner = ScreenshotSession.makeOverlayRunner(allowed: { true }, providerKey: { _ in reads += 1; return "synthetic" },
                streamAI: { connection, _, key, model, _ in await calls.record(connection.id, model, key); return "Unexpected" })
            let overlay = ScreenshotOverlayTranslation(runner: runner, allowed: { true })
            overlay.run(image: try OverlayTranslationTests.image(), lines: OverlayTranslationTests.lines, settings: config)
            await OverlayTranslationTests.settle { overlay.phase != .running }
            XCTAssertEqual(overlay.phase, .failed); XCTAssertNil(overlay.image); XCTAssertEqual(reads, 0)
            let sent = await calls.values; XCTAssertTrue(sent.isEmpty)
            overlay.clear()
        }
    }
}


extension OverlayRoutingTests {
    @MainActor func testOverlayNeverRetriesPartialAuthenticationOrProtectedFailures() async throws {
        for scenario in ["partial", "authentication", "protected"] {
            var config = providerSettings(); config.translation.engine = .ai
            let calls = OverlayProviderCalls(); var allowed = true
            let runner = ScreenshotSession.makeOverlayRunner(allowed: { allowed }, providerKey: { "synthetic-" + $0 },
                streamAI: { connection, _, key, model, delta in
                    await calls.record(connection.id, model, key)
                    if scenario == "authentication" { throw AIClientError.unauthorized }
                    if scenario == "partial" { await delta("Incomplete synthetic output") }
                    else { await MainActor.run { allowed = false } }
                    throw AIClientError.server
                })
            let overlay = ScreenshotOverlayTranslation(runner: runner, allowed: { allowed })
            overlay.run(image: try OverlayTranslationTests.image(), lines: OverlayTranslationTests.lines, settings: config)
            await OverlayTranslationTests.settle { overlay.phase != .running }
            XCTAssertEqual(overlay.phase, .failed, scenario); XCTAssertNil(overlay.image)
            let sent = await calls.values
            XCTAssertEqual(sent, [.init(provider: "translation-provider", model: "translation-task", key: "synthetic-translation-provider")], scenario)
            overlay.clear()
        }
    }
}
