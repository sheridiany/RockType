import AppKit
import XCTest
@testable import RoarkTPlatform

/// Frozen invented content, rendered at 1 pixel per point. Never reads a screen or user file.
final class OCRQualityTests: XCTestCase, @unchecked Sendable {
    struct Fragment {
        let text: String
        let x: CGFloat
        let y: CGFloat
    }
    struct Sample {
        let id: String
        let size: CGSize
        let font: CGFloat
        var dark = false
        var mono = false
        let fragments: [Fragment]
        let expected: String
        let anchors: [String]
    }
    static let samples: [Sample] = [
        .init(id: "chinese", size: .init(width: 780, height: 180), font: 24,
              fragments: [.init(text: "春天的花园里有许多树木", x: 28, y: 20), .init(text: "我们一起阅读新的故事", x: 28, y: 68), .init(text: "明天准备出发去看大海", x: 28, y: 116)],
              expected: "春天的花园里有许多树木\n我们一起阅读新的故事\n明天准备出发去看大海", anchors: ["春天", "阅读", "大海"]),
        .init(id: "english", size: .init(width: 780, height: 180), font: 23,
              fragments: [.init(text: "Morning light fills the quiet garden.", x: 28, y: 20), .init(text: "Please review the latest document.", x: 28, y: 68), .init(text: "Tomorrow we will visit the library.", x: 28, y: 116)],
              expected: "Morning light fills the quiet garden.\nPlease review the latest document.\nTomorrow we will visit the library.", anchors: ["Morning", "Please", "Tomorrow"]),
        .init(id: "mixed", size: .init(width: 780, height: 180), font: 22,
              fragments: [.init(text: "项目 Alpha 已完成第一轮测试", x: 28, y: 20), .init(text: "请检查 API response 和错误信息", x: 28, y: 68), .init(text: "版本 Beta 将在明天发布", x: 28, y: 116)],
              expected: "项目 Alpha 已完成第一轮测试\n请检查 API response 和错误信息\n版本 Beta 将在明天发布", anchors: ["Alpha", "API", "Beta"]),
        .init(id: "code", size: .init(width: 780, height: 240), font: 19, mono: true,
              fragments: [.init(text: "func total(_ values: [Int]) -> Int {", x: 28, y: 20), .init(text: "    var sum = 0", x: 28, y: 54), .init(text: "    for value in values {", x: 28, y: 88), .init(text: "        sum += value", x: 28, y: 122), .init(text: "    }", x: 28, y: 156), .init(text: "    return sum", x: 28, y: 190)],
              expected: "func total(_ values: [Int]) -> Int {\n    var sum = 0\n    for value in values {\n        sum += value\n    }\n    return sum", anchors: ["func", "var", "for", "+=", "return"]),
        .init(id: "table", size: .init(width: 720, height: 210), font: 22, mono: true,
              fragments: [.init(text: "Item", x: 28, y: 20), .init(text: "Count", x: 280, y: 20), .init(text: "Price", x: 510, y: 20), .init(text: "Apple", x: 28, y: 68), .init(text: "12", x: 280, y: 68), .init(text: "$24", x: 510, y: 68), .init(text: "Pear", x: 28, y: 116), .init(text: "18", x: 280, y: 116), .init(text: "$36", x: 510, y: 116), .init(text: "Mango", x: 28, y: 164), .init(text: "20", x: 280, y: 164), .init(text: "$80", x: 510, y: 164)],
              expected: "Item\tCount\tPrice\nApple\t12\t$24\nPear\t18\t$36\nMango\t20\t$80", anchors: ["Item", "Count", "Price", "Apple", "12", "$24", "Pear", "18", "$36", "Mango", "20", "$80"]),
        .init(id: "small", size: .init(width: 440, height: 94), font: 9, mono: true,
              fragments: [.init(text: "Small text remains useful at 9 pixels.", x: 18, y: 15), .init(text: "Sample number 12345 is intentionally tiny.", x: 18, y: 40), .init(text: "Never use private screenshots as fixtures.", x: 18, y: 65)],
              expected: "Small text remains useful at 9 pixels.\nSample number 12345 is intentionally tiny.\nNever use private screenshots as fixtures.", anchors: ["Small", "Sample", "Never"]),
        .init(id: "dark", size: .init(width: 780, height: 180), font: 17, dark: true,
              fragments: [.init(text: "Night mode keeps the background dark.", x: 28, y: 20), .init(text: "Contrast should preserve every character.", x: 28, y: 68), .init(text: "Status: all synthetic checks are ready.", x: 28, y: 116)],
              expected: "Night mode keeps the background dark.\nContrast should preserve every character.\nStatus: all synthetic checks are ready.", anchors: ["Night", "Contrast", "Status"]),
        .init(id: "columns", size: .init(width: 1060, height: 210), font: 21,
              fragments: [.init(text: "Left begins the reading journey.", x: 28, y: 20), .init(text: "Continue down this first column.", x: 28, y: 78), .init(text: "Finish here before moving right.", x: 28, y: 136), .init(text: "Right starts the second section.", x: 570, y: 20), .init(text: "Follow the remaining details.", x: 570, y: 78), .init(text: "Finally the article is complete.", x: 570, y: 136)],
              expected: "Left begins the reading journey.\nContinue down this first column.\nFinish here before moving right.\n\nRight starts the second section.\nFollow the remaining details.\nFinally the article is complete.", anchors: ["Left", "Continue", "Finish", "Right", "Follow", "Finally"])
    ]

    @MainActor static func render(_ sample: Sample) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sample.size.width), pixelsHigh: Int(sample.size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(white: sample.dark ? 0.055 : 1, alpha: 1).setFill()
        NSRect(origin: .zero, size: sample.size).fill()
        let font = sample.mono ? NSFont.monospacedSystemFont(ofSize: sample.font, weight: .regular) : NSFont.systemFont(ofSize: sample.font)
        for fragment in sample.fragments {
            (fragment.text as NSString).draw(at: CGPoint(x: fragment.x, y: sample.size.height - fragment.y - sample.font * 1.3),
                withAttributes: [.font: font, .foregroundColor: NSColor(white: sample.dark ? 0.45 : 0.05, alpha: 1)])
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    static func accuracy(expected: String, actual: String, whitespace: Bool = false) -> Double {
        let a = Array(whitespace ? expected : expected.filter { !$0.isWhitespace })
        let b = Array(whitespace ? actual : actual.filter { !$0.isWhitespace })
        guard !a.isEmpty else { return b.isEmpty ? 1 : 0 }
        var previous = Array(0...b.count)
        for (i, lhs) in a.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, rhs) in b.enumerated() { row[j + 1] = min(row[j] + 1, previous[j + 1] + 1, previous[j] + (lhs == rhs ? 0 : 1)) }
            previous = row
        }
        return max(0, 1 - Double(previous[b.count]) / Double(a.count))
    }
    /// All expected pairs are in the denominator, including pairs with missing anchors.
    static func order(_ anchors: [String], actual: String) -> Double {
        guard anchors.count > 1 else { return anchors.allSatisfy(actual.contains) ? 1 : 0 }
        let positions = anchors.map { actual.range(of: $0)?.lowerBound }
        var correct = 0
        for i in positions.indices { for j in positions.indices where j > i {
            if let lhs = positions[i], let rhs = positions[j], lhs < rhs { correct += 1 }
        } }
        return Double(correct) / Double(anchors.count * (anchors.count - 1) / 2)
    }
    func testMetricsPenalizeMissingAndReversedContent() {
        XCTAssertEqual(Self.accuracy(expected: "abc", actual: "axc"), 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(Self.order(["first", "second", "third"], actual: "third second first"), 0)
        XCTAssertEqual(Self.order(["first", "second", "third"], actual: "first second"), 1.0 / 3)
        XCTAssertEqual(Self.order(["first", "second"], actual: ""), 0)
    }
    func testFrozenSyntheticQualitySuite() async throws {
        var characters = 0.0, order = 0.0, formatting = 0.0
        var baselineCharacters = 0.0, baselineOrder = 0.0, baselineFormatting = 0.0
        for sample in Self.samples {
            let bytes = try await Self.render(sample)
            if sample.id == "dark", ProcessInfo.processInfo.environment["OCR_QUALITY_DEBUG"] == "1", let image = NSBitmapImageRep(data: bytes)?.cgImage {
                let normalized = OCR.contrastImage(image, onlyDark: true)
                try NSBitmapImageRep(cgImage: normalized).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/roarkt-ocr-dark-normalized.png"))
            }
            let baseline = try await R1OCRBaseline().recognize(bytes).text
            let bc = Self.accuracy(expected: sample.expected, actual: baseline)
            let bo = Self.order(sample.anchors, actual: baseline)
            let bf = Self.accuracy(expected: sample.expected, actual: baseline, whitespace: true)
            baselineCharacters += bc; baselineOrder += bo; baselineFormatting += bf
            print(String(format: "OCR_BASELINE %@ characters=%.4f order=%.4f formatting=%.4f", sample.id, bc, bo, bf))
            let result = try await OCR().recognize(bytes)
            let actual = result.text
            let c = Self.accuracy(expected: sample.expected, actual: actual)
            let o = Self.order(sample.anchors, actual: actual)
            let f = Self.accuracy(expected: sample.expected, actual: actual, whitespace: true)
            characters += c; order += o; formatting += f
            print(String(format: "OCR_QUALITY %@ characters=%.4f order=%.4f formatting=%.4f", sample.id, c, o, f))
            if ProcessInfo.processInfo.environment["OCR_QUALITY_DEBUG"] == "1" { print("SYNTHETIC_RESULT \(sample.id): \(actual)") }
            XCTAssertFalse(result.lines.isEmpty, sample.id)
            XCTAssertGreaterThanOrEqual(c + 0.005, bc, "R1 character regression: " + sample.id)
            XCTAssertGreaterThanOrEqual(c, 0.95, "Character regression: " + sample.id)
            XCTAssertGreaterThanOrEqual(o, 0.99, "Reading-order regression: " + sample.id)
            XCTAssertGreaterThanOrEqual(f, 0.90, "Layout regression: " + sample.id)
            if sample.id == "table" {
                XCTAssertEqual(actual.filter { $0 == "\t" }.count, 8)
                XCTAssertEqual(actual.components(separatedBy: "\n").count, 4)
            }
            if sample.id == "code" { XCTAssertTrue(actual.contains("\n        sum")) }
        }
        let count = Double(Self.samples.count)
        XCTAssertGreaterThanOrEqual(characters / count, 0.99)
        XCTAssertGreaterThanOrEqual(order / count, 0.99)
        print(String(format: "OCR_BASELINE MACRO characters=%.4f order=%.4f formatting=%.4f", baselineCharacters / count, baselineOrder / count, baselineFormatting / count))
        print(String(format: "OCR_QUALITY MACRO characters=%.4f order=%.4f formatting=%.4f", characters / count, order / count, formatting / count))
    }
}

extension OCRQualityTests {
    func testDarkContrastVariantRetainsSyntheticCharacters() async throws {
        let sample = try XCTUnwrap(Self.samples.first { $0.id == "dark" })
        let bytes = try await Self.render(sample)
        let image = try XCTUnwrap(NSBitmapImageRep(data: bytes)?.cgImage)
        let enhanced = OCR.contrastImage(image, onlyDark: true)
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: enhanced).representation(using: .png, properties: [:]))
        let result = try await OCR().recognize(data)
        XCTAssertGreaterThanOrEqual(Self.accuracy(expected: sample.expected, actual: result.text), 0.98)
    }
}
