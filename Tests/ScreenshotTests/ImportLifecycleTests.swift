import AppKit
import XCTest
@testable import RoarkTApp

private final class ImportGate: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    let release = DispatchSemaphore(value: 0)
    var entered: Bool { lock.withLock { started } }
    func enter() { lock.withLock { started = true } }
}
final class ImportLifecycleTests: XCTestCase {
    private func image() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(ctx.makeImage())
    }
    @MainActor private func settle(_ predicate: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(predicate())
    }
    @MainActor func testCancelledImportCannotReplaceNewerResult() async throws {
        let image = try image(), gate = ImportGate()
        let importer = ScreenshotImportController(allowed: { true }, decode: { data in
            if data.first == 1 {
                gate.enter(); _ = gate.release.wait(timeout: .now() + 3)
            }
            return image
        })
        var origins: [String] = []
        importer.onImage = { _, origin in origins.append(origin) }
        importer.load(Data([1]), origin: "old")
        await settle { gate.entered }
        importer.load(Data([2]), origin: "new")
        await settle { origins == ["new"] }
        gate.release.signal()
        importer.cancel()
        // Drain the main actor after the old decoder has been released.
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(origins, ["new"])
    }
    @MainActor func testProtectedImportHasNoDecodeOrResultAndErrorsStayGeneric() async throws {
        let image = try image(), gate = ImportGate()
        var allowed = false
        let importer = ScreenshotImportController(allowed: { allowed }, decode: { _ in gate.enter(); return image })
        var completed = false
        importer.onImage = { _, _ in completed = true }
        importer.load(Data(), origin: "synthetic")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(gate.entered); XCTAssertFalse(completed)
        allowed = true
        let failing = ScreenshotImportController(allowed: { allowed }, decode: { _ in throw ScreenshotImageImport.Failure.tooLarge })
        var notice: String?
        failing.onNotice = { notice = $0 }
        failing.load(Data(), origin: "synthetic")
        await settle { notice != nil }
        XCTAssertTrue(notice?.contains("40 MB") == true)
    }
}
