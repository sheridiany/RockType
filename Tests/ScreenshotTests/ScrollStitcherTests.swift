import AppKit
import Foundation
import XCTest
@testable import RoarkTApp

final class ScrollStitcherTests: XCTestCase, @unchecked Sendable {
    /// Every row and column has a deterministic distinct pattern; no captured user content.
    private func image(offset: Int, body: Int = 160, header: Int = 0, footer: Int = 0, period: Int? = nil, width: Int = 96) throws -> CGImage {
        let height = body + header + footer
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let row: Int
                    if y < header { row = 100_000 + y }
                    else if y >= header + body { row = 200_000 + y - header - body }
                    else { row = period.map { (y - header + offset) % $0 } ?? (y - header + offset) }
                    var n = UInt32(truncatingIfNeeded: row &* 747796405 &+ x &* 2891336453 &+ 42)
                    n = ((n >> ((n >> 28) + 4)) ^ n) &* 277803737
                    n = (n >> 22) ^ n
                    let i = (y * width + x) * 4
                    p[i] = UInt8(truncatingIfNeeded: n); p[i + 1] = UInt8(truncatingIfNeeded: n >> 8)
                    p[i + 2] = UInt8(truncatingIfNeeded: n >> 16); p[i + 3] = 255
                }
            }
        }
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func pixels(_ image: CGImage) throws -> Data { try XCTUnwrap(image.dataProvider?.data) as Data }
    @MainActor func testOrdinaryTextPageWithRepeatedLayoutKeepsExactSeams() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 1800, bitsPerComponent: 8, bytesPerRow: 2400,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 600, height: 1800))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for index in 0..<60 {
            let line = "Synthetic item \(index): capture, scroll and verify row \(index * 137)."
            (line as NSString).draw(at: CGPoint(x: 24, y: 1760 - index * 28), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        let document = try XCTUnwrap(context.makeImage()), stitcher = ScrollStitcher()
        for (index, offset) in [0, 96, 240].enumerated() {
            let frame = try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: offset, width: 600, height: 600)))
            let update = try await stitcher.append(frame)
            XCTAssertEqual(update.outcome, index == 0 ? .started : .added)
        }
        let result = try await stitcher.finish()
        XCTAssertEqual(result.height, 840)
        XCTAssertTrue(try pixels(result) == pixels(document).prefix(600 * 840 * 4))
    }
    func testSeveralOffsetsIncludingFastOverlappingJumpHaveExactPixels() async throws {
        let stitcher = ScrollStitcher()
        for (offset, outcome) in [(0, ScrollStitchUpdate.Outcome.started), (24, .added), (120, .added), (184, .added)] {
            let result = try await stitcher.append(image(offset: offset))
            XCTAssertEqual(result.outcome, outcome); XCTAssertEqual(result.height, 160 + offset)
            XCTAssertLessThanOrEqual(try XCTUnwrap(result.thumbnail).height, 540)
        }
        let result = try await stitcher.finish()
        XCTAssertEqual(result.height, 344)
        XCTAssertEqual(try pixels(result), try pixels(image(offset: 0, body: 344)))
    }
    func testStickyHeaderAndFooterAppearExactlyOnce() async throws {
        let stitcher = ScrollStitcher()
        for (index, offset) in [0, 48, 144, 216].enumerated() {
            let result = try await stitcher.append(image(offset: offset, header: 20, footer: 12))
            XCTAssertEqual(result.outcome, index == 0 ? .started : .added)
        }
        let result = try await stitcher.finish()
        XCTAssertEqual(result.height, 408)
        XCTAssertEqual(try pixels(result), try pixels(image(offset: 0, body: 376, header: 20, footer: 12)))
    }
    func testJumpWithoutOverlapRejectsAndCanRecoverWithoutLosingPixels() async throws {
        let stitcher = ScrollStitcher()
        _ = try await stitcher.append(image(offset: 0))
        let gap = try await stitcher.append(image(offset: 500))
        XCTAssertEqual(gap.outcome, .gap); XCTAssertEqual(gap.height, 160)
        let recovery = try await stitcher.append(image(offset: 80))
        XCTAssertEqual(recovery.outcome, .added)
        let result = try await stitcher.finish()
        XCTAssertEqual(try pixels(result), try pixels(image(offset: 0, body: 240)))
    }
    func testRepeatingRowsAreNotGuessedAndIdenticalFramesDoNotGrow() async throws {
        let stitcher = ScrollStitcher()
        let first = try image(offset: 0, period: 16)
        _ = try await stitcher.append(first)
        let same = try await stitcher.append(image(offset: 16, period: 16))
        XCTAssertEqual(same.outcome, .unchanged)
        let ambiguous = try await stitcher.append(image(offset: 5, period: 16))
        XCTAssertEqual(ambiguous.outcome, .ambiguous)
        let result = try await stitcher.finish()
        XCTAssertEqual(try pixels(result), try pixels(first))
    }
    func testStationaryAnimationIsNotReportedAsScrolling() async throws {
        let stitcher = ScrollStitcher(), first = try image(offset: 0)
        _ = try await stitcher.append(first)
        var data = try pixels(first)
        for y in 40..<60 { for x in 20..<40 {
            let i = (y * first.width + x) * 4
            data[i] = 255; data[i + 1] = 0; data[i + 2] = 0
        } }
        let changed = try XCTUnwrap(CGImage(width: first.width, height: first.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: first.width * 4, space: first.colorSpace!, bitmapInfo: first.bitmapInfo,
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let update = try await stitcher.append(changed)
        XCTAssertEqual(update.outcome, .unchanged)
        let result = try await stitcher.finish()
        XCTAssertEqual(try pixels(result), try pixels(first))
    }
    func testReverseAndChangingFixedHeaderDoNotMutateAcceptedImage() async throws {
        let stitcher = ScrollStitcher()
        _ = try await stitcher.append(image(offset: 0, header: 16))
        _ = try await stitcher.append(image(offset: 80, header: 16))
        let reverse = try await stitcher.append(image(offset: 40, header: 16))
        XCTAssertEqual(reverse.outcome, .reversed)
        let changed = try await stitcher.append(image(offset: 120, body: 176))
        XCTAssertEqual(changed.outcome, .ambiguous)
        let result = try await stitcher.finish()
        XCTAssertEqual(try pixels(result), try pixels(image(offset: 0, body: 240, header: 16)))
    }
    func testHeightFrameAndMemoryCapsPreserveLastAcceptedOutputAndResetReleasesState() async throws {
        for limits in [ScrollStitchLimits(maxHeight: 200, maxFrames: 32), ScrollStitchLimits(maxFrames: 1)] {
            let stitcher = ScrollStitcher(limits: limits)
            let first = try image(offset: 0)
            _ = try await stitcher.append(first)
            let limit = try await stitcher.append(image(offset: 80))
            XCTAssertEqual(limit.outcome, .limit)
            let result = try await stitcher.finish()
            XCTAssertEqual(try pixels(result), try pixels(first))
            await stitcher.reset()
            do { _ = try await stitcher.finish(); XCTFail("Reset must discard every strip") } catch ScrollStitcher.Failure.empty { }
        }
        let small = ScrollStitcher(limits: .init(maxBytes: 1_000))
        let rejected = try await small.append(image(offset: 0))
        XCTAssertEqual(rejected.outcome, .limit); XCTAssertNil(rejected.thumbnail); XCTAssertEqual(rejected.height, 0)
    }
    func testScaleOrDimensionChangeFailsRatherThanResizingContent() async throws {
        let stitcher = ScrollStitcher()
        _ = try await stitcher.append(image(offset: 0))
        do { _ = try await stitcher.append(image(offset: 40, width: 192)); XCTFail("Changed scale must fail") }
        catch ScrollStitcher.Failure.dimensions { }
    }
}
