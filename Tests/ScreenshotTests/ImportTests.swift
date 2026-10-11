import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import RoarkTApp

final class ImportTests: XCTestCase {
    func testLosslessPNGDimensionsAndInvalidInput() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = try ScreenshotImageImport.decode(data)
        XCTAssertEqual(image.width, 48); XCTAssertEqual(image.height, 32)
        XCTAssertThrowsError(try ScreenshotImageImport.decode(Data("not an image".utf8)))
        XCTAssertThrowsError(try ScreenshotImageImport.decode(Data(count: ScreenshotImageImport.maximumBytes + 1)))
    }
    func testRejectsRemoteAndDirectoryURLs() {
        XCTAssertThrowsError(try ScreenshotImageImport.read(URL(string: "https://example.invalid/image.png")!))
        XCTAssertThrowsError(try ScreenshotImageImport.read(FileManager.default.temporaryDirectory))
    }
    @MainActor func testDropAcceptsImageAndFileButNotText() {
        XCTAssertEqual(ScreenshotImageImport.type(for: NSItemProvider(item: Data() as NSData, typeIdentifier: UTType.png.identifier)), UTType.png.identifier)
        XCTAssertEqual(ScreenshotImageImport.type(for: NSItemProvider(item: Data() as NSData, typeIdentifier: UTType.fileURL.identifier)), UTType.fileURL.identifier)
        XCTAssertNil(ScreenshotImageImport.type(for: NSItemProvider(item: "synthetic" as NSString, typeIdentifier: UTType.plainText.identifier)))
    }
}
