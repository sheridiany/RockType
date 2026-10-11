import AppKit
import CoreImage
import SwiftUI
import XCTest
import RoarkTPlatform
@testable import RoarkTApp

final class R3RenderingTests: XCTestCase {
    @MainActor func testOverlayOriginalTranslatedAndBarcodeConfirmationInBothThemes() async throws {
        let runner = OverlayTestRunner()
        let session = ScreenshotSession(image: try OverlayTranslationTests.image(), origin: "合成图片", settings: { .defaults }, verified: { _, _ in false },
            allowed: { true }, overlayRunner: runner, scanCodes: { _ in [] })
        defer { session.close() }
        session.previewMode = .overlay
        session.overlay.run(image: try XCTUnwrap(session.image), lines: OverlayTranslationTests.lines, settings: .defaults)
        for dark in [false, true] { try render(session, state: "running", dark: dark) }
        runner.complete("[[RT:0]]\n你好，世界\n[[RT:1]]\n准备继续\n[[RT:END]]")
        await OverlayTranslationTests.settle { session.overlay.phase == .done }
        for translated in [false, true] {
            session.showTranslatedImage = translated
            for dark in [false, true] { try render(session, state: translated ? "translated" : "original", dark: dark) }
        }
        try render(session, state: "narrow-translated", dark: false, width: 460)
        session.overlay.run(image: try XCTUnwrap(session.image), lines: OverlayTranslationTests.lines, settings: .defaults)
        runner.complete("Missing region identifiers", at: 1)
        await OverlayTranslationTests.settle { session.overlay.phase == .failed }
        for dark in [false, true] { try render(session, state: "failed", dark: dark) }
        let qr = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://example.invalid/qr?source=synthetic#complete".utf8)])?.outputImage)
        let codeImage = try XCTUnwrap(CIContext().createCGImage(qr.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: qr.extent.applying(CGAffineTransform(scaleX: 8, y: 8))))
        let codes = ScreenshotSession(image: codeImage, origin: "合成二维码", settings: { .defaults }, verified: { _, _ in false }, allowed: { true }, openURL: { _ in XCTFail("Must not navigate while rendering"); return false })
        defer { codes.close() }
        codes.recognizeCodes()
        await OverlayTranslationTests.settle { codes.barcodes.phase == .done }
        XCTAssertEqual(codes.barcodes.codes.count, 1)
        codes.barcodes.previewURL(at: 0)
        XCTAssertNotNil(codes.barcodes.pendingURL)
        for dark in [false, true] { try render(codes, state: "barcode-confirm", dark: dark) }
        try render(codes, state: "narrow-barcode", dark: false, width: 460)
    }
    @MainActor private func render(_ session: ScreenshotSession, state: String, dark: Bool, width: CGFloat = 900) throws {
        let size = CGSize(width: width, height: 760)
        let hosting = NSHostingView(rootView: ScreenshotPreviewContent(session: session, viewport: size).environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 5000)
        try data.write(to: URL(fileURLWithPath: "/tmp/roarkt-r3-preview-\(state)-\(dark ? "dark" : "light").png"))
    }
}
