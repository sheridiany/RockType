import AppKit
import SwiftUI
import XCTest
import RoarkTCore
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
        var settings = AppSettings.defaults
        settings.ai.visionModel = "synthetic-vision"
        settings.screenshot.skipImageAIConfirmation = true
        var remembered: [Bool] = []
        coordinator.readSettings = { settings }
        coordinator.imageCapabilityVerified = { _, _ in true }
        coordinator.rememberImageConfirmation = {
            remembered.append($0); settings.screenshot.skipImageAIConfirmation = $0
        }
        coordinator.start(); defer { coordinator.stop() }
        coordinator.openImageBatch([url, url])
        var deadline = ContinuousClock.now + .seconds(3)
        while presentations == 0, ContinuousClock.now < deadline { await Task.yield() }
        let imported = try XCTUnwrap(batch)
        XCTAssertEqual(imported.sessions.count, 2)
        XCTAssertNotEqual(imported.current.ocrPhase, .idle)
        XCTAssertNil(coordinator.session); XCTAssertEqual(reads, 0)
        imported.sessions[1].restoreImageConfirmation()
        XCTAssertEqual(remembered, [false])
        imported.sessions[1].text = "Synthetic edited text"
        imported.sessions[1].prepareImage(action: .summarize)
        XCTAssertTrue(imported.sessions[1].confirmingImage)
        XCTAssertEqual(imported.sessions[1].visual.request?.text, "Synthetic edited text")
        coordinator.openClipboardImage()
        XCTAssertTrue(imported.sessions.allSatisfy { $0.image == nil })
        deadline = .now + .seconds(3)
        while coordinator.session == nil, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(presentations, 2); XCTAssertEqual(reads, 1)
        XCTAssertEqual(coordinator.session?.ocrPhase, .idle)
        XCTAssertNil(imported.sessions[1].visual.request)
        coordinator.session?.restoreImageConfirmation()
        XCTAssertEqual(remembered, [false, false])
    }
}
