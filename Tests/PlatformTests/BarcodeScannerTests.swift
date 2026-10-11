import AppKit
import CoreImage
import XCTest
@testable import RoarkTPlatform

final class BarcodeScannerTests: XCTestCase {
    static func syntheticImage() throws -> CGImage {
        let qr = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://example.invalid/qr?source=synthetic#details".utf8), "inputCorrectionLevel": "M"])?.outputImage)
        let bar = try XCTUnwrap(CIFilter(name: "CICode128BarcodeGenerator", parameters: ["inputMessage": Data("TEST-2048".utf8), "inputQuietSpace": 16])?.outputImage)
        let ci = CIContext()
        let context = try XCTUnwrap(CGContext(data: nil, width: 720, height: 440, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 720, height: 440))
        context.interpolationQuality = .none
        context.draw(try XCTUnwrap(ci.createCGImage(qr, from: qr.extent)), in: CGRect(x: 30, y: 210, width: 200, height: 200))
        context.draw(try XCTUnwrap(ci.createCGImage(bar, from: bar.extent)), in: CGRect(x: 280, y: 50, width: 400, height: 120))
        return try XCTUnwrap(context.makeImage())
    }
    func testGeneratedQRAndCode128PayloadsAndTopLeftCoordinates() async throws {
        let image = try Self.syntheticImage()
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let codes = try await BarcodeScanner().recognize(data)
        let qr = try XCTUnwrap(codes.first { $0.payload.contains("example.invalid") })
        let bar = try XCTUnwrap(codes.first { $0.payload == "TEST-2048" })
        XCTAssertTrue(qr.symbology.lowercased().contains("qr")); XCTAssertTrue(bar.symbology.lowercased().contains("128"))
        XCTAssertLessThan(qr.rect.midY, bar.rect.midY)
        XCTAssertLessThan(qr.rect.midX, bar.rect.midX)
        XCTAssertEqual(qr.webURL?.absoluteString, "https://example.invalid/qr?source=synthetic#details")
        XCTAssertNil(bar.webURL)
        try data.write(to: URL(fileURLWithPath: "/tmp/roarkt-r3-barcodes.png"))
    }
    func testURLPolicyAndInvalidImages() async {
        for value in ["javascript:alert(1)", "file:///tmp/example", "https://user:password@example.invalid", "https://", "https://example.invalid/\npath", "not a link"] {
            XCTAssertNil(BarcodeScanner.Code(payload: value, symbology: "synthetic", rect: .zero).webURL)
        }
        for value in ["https://example.invalid/a?b=c#d", "http://example.invalid"] {
            XCTAssertNotNil(BarcodeScanner.Code(payload: value, symbology: "synthetic", rect: .zero).webURL)
        }
        do { _ = try await BarcodeScanner().recognize(Data([0, 1])); XCTFail("Invalid image accepted") } catch {}
        let task = Task { try await BarcodeScanner().recognize(Data([0])) }; task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
