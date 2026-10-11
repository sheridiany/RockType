import AppKit
import XCTest
import RoarkTPlatform
@testable import RoarkTApp

private actor DelayedCodes {
    var continuation: CheckedContinuation<[BarcodeScanner.Code], any Error>?
    func recognize() async throws -> [BarcodeScanner.Code] { try await withCheckedThrowingContinuation { continuation = $0 } }
    var ready: Bool { continuation != nil }
    func finish(_ codes: [BarcodeScanner.Code]) { continuation?.resume(returning: codes); continuation = nil }
}
final class BarcodeWorkflowTests: XCTestCase {
    private static let code = BarcodeScanner.Code(payload: "https://example.invalid/a?b=c#complete", symbology: "QR", rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    @MainActor func testLinkRequiresFullPreviewThenExplicitConfirmationAndProtectionRecheck() async {
        var allowed = true, opened: [URL] = []
        let codes = ScreenshotBarcodes(allowed: { allowed }, recognize: { _ in [Self.code] }, open: { opened.append($0); return true })
        codes.run(Data())
        await OverlayTranslationTests.settle { codes.phase == .done }
        XCTAssertTrue(opened.isEmpty); XCTAssertNil(codes.pendingURL)
        XCTAssertFalse(codes.confirmURL()); XCTAssertTrue(opened.isEmpty)
        codes.previewURL(at: 0)
        XCTAssertEqual(codes.pendingURL?.absoluteString, Self.code.payload); XCTAssertTrue(opened.isEmpty)
        codes.dismissURL(); XCTAssertFalse(codes.confirmURL())
        codes.previewURL(at: 0); allowed = false
        XCTAssertFalse(codes.confirmURL()); XCTAssertTrue(opened.isEmpty)
        allowed = true; codes.previewURL(at: 0); XCTAssertTrue(codes.confirmURL())
        XCTAssertEqual(opened.map(\.absoluteString), [Self.code.payload]); XCTAssertNil(codes.pendingURL)
        XCTAssertFalse(codes.confirmURL()); codes.clear(); XCTAssertTrue(codes.codes.isEmpty)
    }
    @MainActor func testClosingPreviewDropsDelayedBarcodeAndOCRAlsoStartsScanner() async throws {
        let delayed = DelayedCodes()
        let session = ScreenshotSession(image: try OverlayTranslationTests.image(), origin: "synthetic", settings: { .defaults }, verified: { _, _ in false },
            allowed: { true }, recognize: { _ in "Synthetic OCR" }, scanCodes: { _ in try await delayed.recognize() })
        session.runOCR()
        for _ in 0..<100 { if await delayed.ready { break }; await Task.yield() }
        let ready = await delayed.ready; XCTAssertTrue(ready)
        await OverlayTranslationTests.settle { session.ocrFinished }
        session.close(); await delayed.finish([Self.code]); await Task.yield()
        XCTAssertTrue(session.barcodes.codes.isEmpty); XCTAssertNil(session.barcodes.pendingURL)
        XCTAssertNil(session.image)
    }
    @MainActor func testNonURLCodeCanBeReadButNotOpenedAndBlankImageIsNotAnError() async {
        let codes = ScreenshotBarcodes(allowed: { true }, recognize: { _ in [.init(payload: "TEST-2048", symbology: "Code128", rect: .zero)] }, open: { _ in XCTFail("Unexpected navigation"); return false })
        codes.run(Data()); await OverlayTranslationTests.settle { codes.phase == .done }
        XCTAssertEqual(codes.codes.first?.payload, "TEST-2048")
        codes.previewURL(at: 0); XCTAssertNil(codes.pendingURL)
        XCTAssertFalse(codes.confirmURL()); codes.clear()
    }
}
