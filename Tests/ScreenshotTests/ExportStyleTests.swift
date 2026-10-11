import AppKit
import RoarkTCore
import XCTest
@testable import RoarkTApp

final class ExportStyleTests: XCTestCase {
    private func image() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(NSColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 80, width: 200, height: 80))
        ctx.setFillColor(NSColor.blue.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 80))
        return try XCTUnwrap(ctx.makeImage())
    }
    func testDefaultAndDisabledOptionDecodeRoundTrip() throws {
        let old = Data(#"{"format":"png","ocrLanguages":["en-US"]}"#.utf8)
        var settings = try JSONDecoder().decode(ScreenshotSettings.self, from: old)
        XCTAssertTrue(settings.roundedCorners ?? true)
        settings.roundedCorners = false
        XCTAssertEqual(try JSONDecoder().decode(ScreenshotSettings.self, from: JSONEncoder().encode(settings)).roundedCorners, false)
    }
    func testRetinaRoundedAlphaDimensionsOrientationAndSquareOptOut() throws {
        let source = try image()
        let rounded = try XCTUnwrap(ScreenshotExport.render(image: source, pointSize: CGSize(width: 100, height: 80), roundedCorners: true))
        let bitmap = NSBitmapImageRep(cgImage: rounded)
        XCTAssertEqual(rounded.width, 200); XCTAssertEqual(rounded.height, 160)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 16, y: 0)).alphaComponent, 0.99)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 50, y: 20)?.usingColorSpace(.deviceRGB)).redComponent, 0.99)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 50, y: 140)?.usingColorSpace(.deviceRGB)).blueComponent, 0.99)
        let square = try XCTUnwrap(ScreenshotExport.render(image: source, pointSize: CGSize(width: 100, height: 80), roundedCorners: false))
        XCTAssertTrue(square === source)
        XCTAssertGreaterThan(try XCTUnwrap(NSBitmapImageRep(cgImage: square).colorAt(x: 0, y: 0)).alphaComponent, 0.99)
    }
    func testJPEGFlattensCornersWhiteAndPNGPreservesTransparency() throws {
        let output = try XCTUnwrap(ScreenshotExport.render(image: try image(), pointSize: CGSize(width: 100, height: 80), roundedCorners: true))
        let jpeg = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(ScreenshotExport.encode(output, jpeg: true))))
        let png = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(ScreenshotExport.encode(output, jpeg: false))))
        let corner = try XCTUnwrap(jpeg.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(min(corner.redComponent, corner.greenComponent, corner.blueComponent), 0.9)
        XCTAssertLessThan(try XCTUnwrap(png.colorAt(x: 0, y: 0)).alphaComponent, 0.01)
    }
}
