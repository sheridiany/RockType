import AppKit
import SwiftUI
import XCTest
@testable import RoarkTApp

final class MergeImportTests: XCTestCase {
    @MainActor func testBatchPreviewInjectionAndClipboardEntryShareCoordinatorWithoutLosingSaveInjection() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("synthetic.png"); try data.write(to: url)
        var batch: ScreenshotBatch?, presentations = 0, reads = 0
        let save = ScreenshotSaveAsController(allowed: { true }, choose: { _, _ in
            XCTFail("Import must not open a save dialog"); return {}
        })
        let coordinator = ScreenshotCoordinator(captureFrames: { [] }, allowed: { true }, saveAs: save,
            readClipboard: { reads += 1; return data }, presentPreview: { panel in
                presentations += 1
                if let host = panel.contentView as? NSHostingView<ScreenshotBatchPreview> { batch = host.rootView.batch }
            })
        coordinator.start(); defer { coordinator.stop() }
        coordinator.openImageBatch([url, url])
        var deadline = ContinuousClock.now + .seconds(3)
        while presentations == 0, ContinuousClock.now < deadline { await Task.yield() }
        let imported = try XCTUnwrap(batch)
        XCTAssertEqual(imported.sessions.count, 2)
        XCTAssertNotEqual(imported.current.ocrPhase, .idle)
        XCTAssertNil(coordinator.session); XCTAssertEqual(reads, 0)
        coordinator.openClipboardImage()
        XCTAssertTrue(imported.sessions.allSatisfy { $0.image == nil })
        deadline = .now + .seconds(3)
        while coordinator.session == nil, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(presentations, 2); XCTAssertEqual(reads, 1)
        XCTAssertEqual(coordinator.session?.ocrPhase, .idle)
    }
}
