import XCTest
import AppKit
import RoarkTCore
@testable import RoarkTApp

final class OutputTests: XCTestCase {
    @MainActor func testFilenameDirectoryAndSettingsRoundTrip() throws {
        XCTAssertEqual(ScreenshotOutput.filename(at: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!), "RockType-19700101-000000.png")
        var settings = ScreenshotSettings()
        XCTAssertEqual(try ScreenshotOutput.directory(settings, home: URL(fileURLWithPath: "/synthetic")).path, "/synthetic/Pictures/RockType")
        settings.saveDirectory = "/tmp/a folder/截图"
        XCTAssertEqual(try JSONDecoder().decode(ScreenshotSettings.self, from: JSONEncoder().encode(settings)), settings)
        settings.saveDirectory = "relative"
        XCTAssertThrowsError(try ScreenshotOutput.directory(settings))
    }

    @MainActor func testSaveCollisionCopyAndProtection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = ScreenshotSettings(); settings.saveDirectory = folder.path
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var allowed = true
        let output = ScreenshotOutput(settings: { settings }, allowed: { allowed },
                                      now: { Date(timeIntervalSince1970: 0) }, pasteboard: board)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try XCTUnwrap(bitmap.cgImage)
        let first = try output.save(image)
        let bytes = try Data(contentsOf: first)
        let second = try output.save(image)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: bytes))
        XCTAssertEqual(decoded.pixelsWide, 8); XCTAssertEqual(decoded.pixelsHigh, 4)
        try output.copyPath(first)
        XCTAssertEqual(board.string(forType: .string), first.path)
        allowed = false
        let count = board.changeCount
        XCTAssertThrowsError(try output.save(image))
        XCTAssertThrowsError(try output.copyPath(second))
        XCTAssertThrowsError(try output.copyImage(image))
        XCTAssertEqual(board.changeCount, count)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }
}
