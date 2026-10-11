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
        importer.onImage = { _, origin, _ in origins.append(origin) }
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
        importer.onImage = { _, _, _ in completed = true }
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


extension ImportLifecycleTests {
    @MainActor func testRecognizeFlagBelongsToEachSingleImport() async throws {
        let image = try image()
        let importer = ScreenshotImportController(allowed: { true }, decode: { _ in image })
        var flags: [Bool] = []
        importer.onImage = { _, _, recognize in flags.append(recognize) }
        importer.load(Data(), origin: "OCR", recognize: true)
        await settle { flags.count == 1 }
        importer.load(Data(), origin: "preview")
        await settle { flags.count == 2 }
        XCTAssertEqual(flags, [true, false])
    }
    @MainActor func testSingleAndBatchImportsInvalidateEachOther() async throws {
        let image = try image()
        for firstIsBatch in [true, false] {
            let gate = ImportGate()
            let importer = ScreenshotImportController(allowed: { true }, decode: { _ in
                if !firstIsBatch { gate.enter(); _ = gate.release.wait(timeout: .now() + 3) }
                return image
            }, loadBatch: { _ in
                if firstIsBatch { gate.enter(); _ = gate.release.wait(timeout: .now() + 3) }
                return [image]
            })
            var results: [String] = []
            importer.onImage = { _, _, _ in results.append("single") }
            importer.onBatch = { _ in results.append("batch") }
            if firstIsBatch { importer.load([URL(fileURLWithPath: "/synthetic.png")]) }
            else { importer.load(Data(), origin: "synthetic") }
            await settle { gate.entered }
            if firstIsBatch { importer.load(Data(), origin: "synthetic") }
            else { importer.load([URL(fileURLWithPath: "/synthetic.png")]) }
            let expected = firstIsBatch ? "single" : "batch"
            await settle { results == [expected] }
            gate.release.signal()
            for _ in 0..<50 { await Task.yield() }
            XCTAssertEqual(results, [expected])
            importer.cancel()
        }
    }
    @MainActor func testBatchFailureKeepsIncomingMessageAndProtectionSkipsLoading() async {
        var allowed = false
        let gate = ImportGate()
        let importer = ScreenshotImportController(allowed: { allowed }, loadBatch: { _ in
            gate.enter(); throw ScreenshotImageImport.Failure.tooLarge
        })
        var notices: [String] = []
        importer.onNotice = { notices.append($0) }
        importer.load([URL(fileURLWithPath: "/synthetic.png")])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(gate.entered); XCTAssertTrue(notices.isEmpty)
        allowed = true; importer.load([URL(fileURLWithPath: "/synthetic.png")])
        await settle { !notices.isEmpty }
        XCTAssertEqual(notices, ["无法打开这批图片。请选择最多 10 张 PNG、JPEG 或 TIFF，总像素内存不超过 128 MB。"])
    }
}
