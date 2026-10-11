import AppKit
import XCTest
@testable import RoarkTApp

final class PixelSamplerTests: XCTestCase {
    private func image(width: Int = 200, height: Int = 100) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        return try XCTUnwrap(context.makeImage())
    }
    func testRetinaSamplingTopLeftColorAndExactPixelAtEveryEdge() throws {
        let image = try image(), size = CGSize(width: 100, height: 50)
        let first = try XCTUnwrap(CapturePixelSampler.sample(image: image, point: .zero, size: size))
        XCTAssertEqual(first.hex, "#FF0000"); XCTAssertEqual(first.pixel, .zero)
        XCTAssertEqual(first.targetInPatch, .zero)
        let last = try XCTUnwrap(CapturePixelSampler.sample(image: image, point: CGPoint(x: 99.9, y: 49.9), size: size))
        XCTAssertEqual(last.hex, "#0000FF"); XCTAssertEqual(last.pixel, CGPoint(x: 199, y: 99))
        XCTAssertEqual(last.targetInPatch, CGPoint(x: 7, y: 7))
        XCTAssertEqual(last.patch.width, 8); XCTAssertEqual(last.patch.height, 8)
        XCTAssertNil(CapturePixelSampler.sample(image: image, point: CGPoint(x: 100, y: 5), size: size))
        XCTAssertNil(CapturePixelSampler.sample(image: image, point: CGPoint(x: -0.1, y: 5), size: size))
    }
    func testDisplayScaleIsPerImageAndLensRemainsOnItsDisplay() throws {
        let image = try image()
        let atOneX = try XCTUnwrap(CapturePixelSampler.sample(image: image, point: CGPoint(x: 40, y: 30), size: CGSize(width: 200, height: 100)))
        let atTwoX = try XCTUnwrap(CapturePixelSampler.sample(image: image, point: CGPoint(x: 40, y: 30), size: CGSize(width: 100, height: 50)))
        XCTAssertEqual(atOneX.pixel, CGPoint(x: 40, y: 30)); XCTAssertEqual(atOneX.hex, "#FF0000")
        XCTAssertEqual(atTwoX.pixel, CGPoint(x: 80, y: 60)); XCTAssertEqual(atTwoX.hex, "#0000FF")
        for bounds in [CGRect(x: 0, y: 0, width: 800, height: 600), CGRect(x: -1440, y: -200, width: 1440, height: 900)] {
            for point in [bounds.origin, CGPoint(x: bounds.maxX - 1, y: bounds.maxY - 1)] {
                XCTAssertTrue(bounds.contains(CapturePixelSampler.frame(near: point, bounds: bounds)))
            }
        }
    }
    func testRepeatedLargeImageSamplesRemainSmallAndReportTiming() throws {
        let image = try image(width: 3840, height: 2160)
        let start = ContinuousClock.now
        for i in 0..<500 {
            let sample = try XCTUnwrap(CapturePixelSampler.sample(image: image,
                point: CGPoint(x: (i * 17) % 1920, y: (i * 11) % 1080), size: CGSize(width: 1920, height: 1080)))
            XCTAssertLessThanOrEqual(sample.patch.width, 15); XCTAssertLessThanOrEqual(sample.patch.height, 15)
        }
        // Evidence only; machine load and AppKit display latency are not controlled by this test.
        print("synthetic_500_pixel_samples_duration \(start.duration(to: .now))")
    }
}

extension PixelSamplerTests {
    @MainActor func testSyntheticMagnifierRendersPixelsAndLabel() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in 0..<40 {
            for x in 0..<40 {
                context.setFillColor(CGColor(srgbRed: CGFloat(x) / 40, green: CGFloat(y) / 40, blue: (x + y) % 2 == 0 ? 0.3 : 0.7, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = try XCTUnwrap(context.makeImage())
        let sample = try XCTUnwrap(CapturePixelSampler.sample(image: image, point: CGPoint(x: 20, y: 20), size: CGSize(width: 40, height: 40)))
        let view = CaptureMagnifier(frame: CGRect(x: 0, y: 0, width: 142, height: 170)); view.sample = sample
        let panel = CapturePanel(captureRect: view.bounds)
        panel.ignoresMouseEvents = true
        panel.setFrameOrigin(CGPoint(x: (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 100, y: 0))
        panel.contentView = view; panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil; panel.close() }
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        var labelPixels = 0
        for y in Int(144 * scale)..<Int(162 * scale) {
            for x in Int(10 * scale)..<Int(130 * scale) {
                let pixel = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.8 { labelPixels += 1 }
            }
        }
        XCTAssertGreaterThan(labelPixels, 20)
        if let directory = ProcessInfo.processInfo.environment["ROARKT_SHOT_ARTIFACTS"] {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("magnifier.png"))
        }
    }
}
