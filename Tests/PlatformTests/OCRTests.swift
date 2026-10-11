import XCTest
@testable import RoarkTPlatform

final class OCRTests: XCTestCase, @unchecked Sendable {
    func testSyntheticFixture() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ocr-sample", withExtension: "png", subdirectory: "Fixtures"))
        let result = try await OCR(checkReadable: {}).recognize(Data(contentsOf: url))
        for expected in ["OCR", "12345", "本地识别"] { XCTAssertTrue(result.text.contains(expected), "Missing synthetic sample token") }
        XCTAssertFalse(result.lines.isEmpty)
        for line in result.lines {
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(line.rect))
            XCTAssertGreaterThan(line.rect.height, 0)
        }
    }

    func testInvalidImage() async {
        do { _ = try await OCR(checkReadable: {}).recognize(Data([0, 1])); XCTFail("Must reject invalid image") }
        catch { XCTAssertTrue(error is OCR.Failure) }
    }

    func testSecureInputRejectsBeforeDecode() async {
        do { _ = try await OCR(checkReadable: { throw PlatformReadError.secureInput }).recognize(Data()); XCTFail("Must refuse") }
        catch { XCTAssertEqual(error as? PlatformReadError, .secureInput) }
    }
}
