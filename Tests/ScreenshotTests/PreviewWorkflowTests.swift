import AppKit
import XCTest
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class PreviewRunner: OperationRunner {
    var requests: [OperationRequest] = []
    var sinks: [AsyncStream<OperationEvent>.Continuation] = []
    var stops = 0
    func start() {}
    func stop() { stops += 1 }
    func cancel() { stops += 1 }
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        requests.append(request)
        return AsyncStream { sinks.append($0) }
    }
}
final class PreviewWorkflowTests: XCTestCase {
    private func image() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        return try XCTUnwrap(ctx.makeImage())
    }
    @MainActor private func settle(_ ready: () -> Bool) async {
        for _ in 0..<100 where !ready() { try? await Task.sleep(for: .milliseconds(5)) }
    }
    @MainActor func testTranslationUsesEditsAndDropsOldStreamAfterEditingOrClose() async throws {
        let runner = PreviewRunner()
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { .defaults }, verified: { _, _ in false },
            allowed: { true }, recognize: { _ in "Synthetic OCR" }, translationRunner: runner)
        session.text = "Corrected source"
        session.translate()
        XCTAssertEqual(runner.requests.first?.session.snapshot.text, "Corrected source")
        XCTAssertEqual(runner.requests.first?.session.snapshot.method, .screenshotOCR)
        runner.sinks[0].yield(.engine("Synthetic engine")); runner.sinks[0].yield(.delta("Partial translation"))
        await settle { session.translation.text == "Partial translation" }
        XCTAssertEqual(session.translation.phase, .running)
        session.text = "New source"
        runner.sinks[0].yield(.delta(" stale"))
        await settle { session.translation.phase == .idle }
        XCTAssertEqual(session.translation.text, "")
        session.translate()
        let request = try XCTUnwrap(runner.requests.last)
        runner.sinks[1].yield(.completed(.init(session: request.session, templateID: "translate", text: "New translation", engine: "synthetic")))
        await settle { session.translation.phase == .done }
        XCTAssertEqual(session.translation.text, "New translation")
        session.close()
        XCTAssertEqual(session.translation.phase, .idle); XCTAssertTrue(session.translation.text.isEmpty)
        XCTAssertGreaterThan(runner.stops, 0)
    }
    @MainActor func testTranslationCancellationErrorsAndProtectedInput() async throws {
        var allowed = true
        let runner = PreviewRunner()
        let session = ScreenshotSession(image: try image(), origin: "synthetic", settings: { .defaults }, verified: { _, _ in false },
            allowed: { allowed }, translationRunner: runner)
        defer { session.close() }
        session.text = "Synthetic text"; session.translate()
        session.translation.cancel(); runner.sinks[0].yield(.delta("Late"))
        await settle { session.translation.phase == .cancelled }
        XCTAssertTrue(session.translation.text.isEmpty)
        session.translate(); runner.sinks[1].finish()
        await settle { session.translation.phase == .failed }
        XCTAssertEqual(session.translation.phase, .failed)
        session.translate(); allowed = false
        runner.sinks[2].yield(.delta("Protected"))
        await settle { session.translation.phase == .failed }
        XCTAssertTrue(session.translation.text.isEmpty)
        session.translate(); XCTAssertEqual(runner.requests.count, 3)
    }
    @MainActor func testBatchPreservesEditsAndClearsEveryImageOnClose() async throws {
        var completions: [CheckedContinuation<String, any Error>] = []
        func make() throws -> ScreenshotSession {
            ScreenshotSession(image: try image(), origin: "synthetic", settings: { .defaults }, verified: { _, _ in false },
                allowed: { true }, recognize: { _ in try await withCheckedThrowingContinuation { completions.append($0) } }, translationRunner: PreviewRunner())
        }
        let first = try make(), second = try make()
        let batch = ScreenshotBatch(sessions: [first, second])
        first.runOCR(); await settle { completions.count == 1 }
        batch.select(1); await settle { completions.count == 2 }
        completions[0].resume(returning: "Late first image")
        completions[1].resume(returning: "Second image")
        await settle { second.ocrFinished }
        XCTAssertTrue(first.text.isEmpty); XCTAssertEqual(second.text, "Second image")
        second.text = "Edited second image"
        batch.select(0); await settle { completions.count == 3 }
        completions[2].resume(returning: "First image")
        await settle { first.ocrFinished }
        batch.select(1)
        XCTAssertEqual(second.text, "Edited second image")
        batch.close()
        XCTAssertTrue(batch.sessions.allSatisfy { $0.image == nil && $0.text.isEmpty })
    }
    func testBatchCountAndInvalidFilesAreRejected() {
        XCTAssertThrowsError(try ScreenshotBatch.load([]))
        XCTAssertThrowsError(try ScreenshotBatch.load(Array(repeating: URL(fileURLWithPath: "/invalid-synthetic.png"), count: 11)))
        XCTAssertThrowsError(try ScreenshotBatch.load([URL(string: "https://example.invalid/test.png")!]))
    }
    @MainActor func testClipboardOCREntryOnlyReadsOnExplicitAction() async throws {
        var reads = 0, allowed = true
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: try image()).representation(using: .png, properties: [:]))
        let coordinator = ScreenshotCoordinator(captureFrames: { [] }, allowed: { allowed }, readClipboard: { reads += 1; return data }, presentPreview: { _ in })
        coordinator.start(); defer { coordinator.stop() }
        XCTAssertEqual(reads, 0)
        allowed = false; coordinator.openClipboardImage(recognize: true); XCTAssertEqual(reads, 0)
        allowed = true; coordinator.openClipboardImage(recognize: true)
        await settle { coordinator.session != nil }
        XCTAssertEqual(reads, 1)
        XCTAssertNotEqual(coordinator.session?.ocrPhase, .idle)
        coordinator.closePreview()
        coordinator.openClipboardImage(recognize: true); coordinator.cancel()
        await settle { coordinator.session != nil }
        XCTAssertNil(coordinator.session)
    }
}

extension PreviewWorkflowTests {
    func testBatchLoadsSyntheticImagesInSelectionOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roarkt-batch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try image(), second = try XCTUnwrap(first.cropping(to: CGRect(x: 0, y: 0, width: 40, height: 40)))
        let urls = [directory.appendingPathComponent("first.png"), directory.appendingPathComponent("second.png")]
        for (index, image) in [first, second].enumerated() {
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: urls[index])
        }
        let images = try ScreenshotBatch.load(urls)
        XCTAssertEqual(images.map(\.width), [80, 40])
    }
}
