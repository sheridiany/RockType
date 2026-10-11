import AppKit

import XCTest
@testable import RoarkTPlatform

final class OCRTests: XCTestCase, @unchecked Sendable {
    func testSyntheticFixture() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ocr-sample", withExtension: "png", subdirectory: "Fixtures"))
        let result = try await OCR().recognize(Data(contentsOf: url))
        for expected in ["OCR", "12345", "本地识别"] { XCTAssertTrue(result.text.contains(expected), "Missing synthetic sample token") }
        XCTAssertFalse(result.lines.isEmpty)
        for line in result.lines {
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(line.rect))
            XCTAssertGreaterThan(line.rect.height, 0)
        }
    }

    func testInvalidImage() async {
        do { _ = try await OCR().recognize(Data([0, 1])); XCTFail("Must reject invalid image") }
        catch { XCTAssertTrue(error is OCR.Failure) }
    }
}

extension OCRTests {
    func testLayoutPreservesIndentListsAndParagraphs() {
        func line(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 0.4) -> OCR.Line {
            .init(text: text, rect: CGRect(x: x, y: y, width: width, height: 0.04))
        }
        let prose = OCR.Result(lines: [line("中文", 0.1, 0.1), line("段落", 0.1, 0.15)])
        XCTAssertEqual(prose.text, "中文\n段落")
        XCTAssertEqual(prose.formatted(paragraphs: true), "中文段落")
        let english = OCR.Result(lines: [line("Hello", 0.1, 0.1), line("world", 0.1, 0.15)])
        XCTAssertEqual(english.formatted(paragraphs: true), "Hello world")
        let code = OCR.Result(lines: [line("if ready {", 0.1, 0.1), line("return 42;", 0.18, 0.15), line("}", 0.1, 0.2)])
        XCTAssertEqual(code.text, "if ready {\n  return 42;\n}")
        let lists = OCR.Result(lines: [line("Title", 0.1, 0.1), line("1. First", 0.1, 0.15), line("2. Second", 0.1, 0.2), line("End", 0.1, 0.35)])
        XCTAssertEqual(lists.formatted(paragraphs: true), "Title\n1. First\n2. Second\n\nEnd")
    }

    @MainActor func testGeneratedSmallTextAndLanguageSelection() async throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 500, pixelsHigh: 70,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 500, height: 70).fill()
        ("Synthetic OCR 12345" as NSString).draw(at: NSPoint(x: 16, y: 28),
            withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let result = try await OCR().recognize(data, languages: ["en-US", "ja-JP", "ko-KR"])
        XCTAssertTrue(result.text.contains("12345"))
        XCTAssertFalse(result.lines.isEmpty)
    }
}
