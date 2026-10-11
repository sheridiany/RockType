import AppKit
import XCTest
import RoarkTCore
import RoarkTPlatform
@testable import RoarkTApp

@MainActor final class OverlayTestRunner: OperationRunner {
    var requests: [OperationRequest] = []
    var sinks: [AsyncStream<OperationEvent>.Continuation] = []
    var stopped = 0
    func start() {}
    func stop() { stopped += 1 }
    func cancel() { stopped += 1 }
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        requests.append(request); return AsyncStream { sinks.append($0) }
    }
    func complete(_ text: String, at index: Int = 0) {
        sinks[index].yield(.completed(.init(session: requests[index].session, templateID: "translate", text: text, engine: "Synthetic")))
    }
}
final class OverlayTranslationTests: XCTestCase {
    static let lines: [OCR.Line] = [
        .init(text: "Hello world", rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.2)),
        .init(text: "Ready to continue", rect: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.2))]
    static func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
        context.setFillColor(CGColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 600, height: 150))
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("Hello world" as NSString).draw(at: CGPoint(x: 68, y: 220), withAttributes: [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.black])
        ("Ready to continue" as NSString).draw(at: CGPoint(x: 68, y: 70), withAttributes: [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.white])
        return try XCTUnwrap(context.makeImage())
    }
    @MainActor static func settle(_ ready: @escaping @MainActor () -> Bool) async {
        for _ in 0..<200 where !ready() { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(ready())
    }
    func testCompleteMappingsAllowReorderButRejectMissingDuplicateAndInventedIDs() throws {
        XCTAssertEqual(try ScreenshotOverlayTranslation.parse("[[RT:1]]\n继续\n[[RT:0]]\n你好\n[[RT:END]]", count: 2), ["你好", "继续"])
        XCTAssertEqual(try ScreenshotOverlayTranslation.parse("\n\t[[RT:0]]\n你好🌍\n[[RT:END]]\n", count: 1), ["你好🌍"])
        for malformed in ["你好\n继续", "[[RT:0]]\n你好", "[[RT:0]]\na\n[[RT:0]]\nb", "[[RT:2]]\na\n[[RT:1]]\nb", "说明\n[[RT:0]]\na\n[[RT:1]]\nb", "[[RT:0]]\n[[RT:1]]\nb"] {
            XCTAssertThrowsError(try ScreenshotOverlayTranslation.parse(malformed + "\n[[RT:END]]", count: 2))
        }
    }
    func testMissingTerminatorAndOversizedOutputAreRejected() {
        XCTAssertThrowsError(try ScreenshotOverlayTranslation.parse("[[RT:0]]\nIncomplete", count: 1))
        XCTAssertThrowsError(try ScreenshotOverlayTranslation.parse("[[RT:0]]\n" + String(repeating: "x", count: 65_537) + "\n[[RT:END]]", count: 1))
    }
    func testRenderKeepsSizeAndOutsidePixelsAndFitsBothBackgrounds() throws {
        let original = try Self.image()
        let result = try ScreenshotTranslatedImageRenderer.render(original, lines: Self.lines, translations: ["你好，世界", "准备好继续"])
        XCTAssertEqual(result.width, original.width); XCTAssertEqual(result.height, original.height)
        let before = NSBitmapImageRep(cgImage: original), after = NSBitmapImageRep(cgImage: result)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 140), CGPoint(x: 599, y: 299), CGPoint(x: 61, y: 31), CGPoint(x: 61, y: 181)] {
            let a = try XCTUnwrap(before.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.deviceRGB))
            let b = try XCTUnwrap(after.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.01)
            XCTAssertEqual(a.blueComponent, b.blueComponent, accuracy: 0.01)
        }
        var changedTop = 0, changedBottom = 0
        for y in 30..<90 { for x in 60..<540 {
            if before.colorAt(x: x, y: y) != after.colorAt(x: x, y: y) { changedTop += 1 }
            if before.colorAt(x: x, y: y + 150) != after.colorAt(x: x, y: y + 150) { changedBottom += 1 }
        } }
        XCTAssertGreaterThan(changedTop, 300); XCTAssertGreaterThan(changedBottom, 300)
        for (name, bitmap) in [("original", before), ("translated", after)] {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/roarkt-r3-\(name).png"))
        }
        XCTAssertThrowsError(try ScreenshotTranslatedImageRenderer.render(original,
            lines: [.init(text: "outside", rect: CGRect(x: 1.000001, y: 0, width: 0.000001, height: 0.2))], translations: ["区域外"]))
        XCTAssertThrowsError(try ScreenshotTranslatedImageRenderer.render(original, lines: Self.lines, translations: [String(repeating: "very long ", count: 3000), "text"]))
    }
    func testRenderedChineseIsRecognizableWithRealVision() async throws {
        let rendered = try ScreenshotTranslatedImageRenderer.render(Self.image(), lines: Self.lines, translations: ["你好，世界", "准备好继续"])
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
        let result = try await OCR().recognize(png, languages: ["zh-Hans"])
        let text = result.text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "")
        XCTAssertTrue(text.contains("你好")); XCTAssertTrue(text.contains("世界")); XCTAssertTrue(text.contains("准备好继续"))
    }
    @MainActor func testSingleBatchRequestAndCancelOrEditDropsLateCompletion() async throws {
        let runner = OverlayTestRunner(), image = try Self.image()
        let overlay = ScreenshotOverlayTranslation(runner: runner, allowed: { true })
        overlay.run(image: image, lines: Self.lines, settings: .defaults)
        XCTAssertEqual(runner.requests.count, 1)
        XCTAssertEqual(runner.requests[0].template.id, "translate")
        XCTAssertEqual(runner.requests[0].settings.translation.engine, .offlineFirst)
        XCTAssertTrue(runner.requests[0].session.snapshot.text.contains(Self.lines[0].text))
        XCTAssertTrue(runner.requests[0].session.snapshot.text.contains(Self.lines[1].text))
        overlay.cancel(); runner.complete("[[RT:0]]\n你好\n[[RT:1]]\n继续\n[[RT:END]]")
        await Task.yield(); XCTAssertNil(overlay.image); XCTAssertEqual(overlay.phase, .cancelled)
        overlay.run(image: image, lines: Self.lines, settings: .defaults)
        runner.complete("[[RT:0]]\n你好\n[[RT:1]]\n继续\n[[RT:END]]", at: 1)
        await Self.settle { overlay.phase == .done }
        XCTAssertNotNil(overlay.image)
        overlay.clear(); XCTAssertNil(overlay.image)
    }
    @MainActor func testIncompleteMappingAndSecureInputCannotProduceImage() async throws {
        let runner = OverlayTestRunner(); var allowed = true
        let overlay = ScreenshotOverlayTranslation(runner: runner, allowed: { allowed })
        overlay.run(image: try Self.image(), lines: Self.lines, settings: .defaults)
        runner.complete("[[RT:0]]\n你好")
        await Self.settle { overlay.phase == .failed }; XCTAssertNil(overlay.image)
        overlay.run(image: try Self.image(), lines: Self.lines, settings: .defaults)
        allowed = false; runner.complete("[[RT:0]]\n你好\n[[RT:1]]\n继续\n[[RT:END]]", at: 1)
        await Self.settle { overlay.phase == .failed }; XCTAssertNil(overlay.image)
        overlay.run(image: try Self.image(), lines: Self.lines, settings: .defaults)
        XCTAssertEqual(runner.requests.count, 2)
    }
}
