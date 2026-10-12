import AppKit
import RoarkTCore
import XCTest
@testable import RoarkTApp

final class SaveAsTests: XCTestCase {
    private func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 30, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
    @MainActor func testCancelDuplicateDialogAndLateReplyNeverWrite() throws {
        var reply: ((URL?) -> Void)?
        var presented = 0, dismissed = 0, written = 0
        var outcomes: [ScreenshotSaveAsController.Outcome] = []
        let controller = ScreenshotSaveAsController(allowed: { true }, choose: { _, callback in
            presented += 1; reply = callback; return { dismissed += 1 }
        }, write: { _, _ in written += 1 })
        controller.present(image: try image(), format: .png) { outcomes.append($0) }
        controller.present(image: try image(), format: .png) { outcomes.append($0) }
        XCTAssertEqual(presented, 1)
        controller.cancel()
        reply?(URL(fileURLWithPath: "/synthetic.png"))
        XCTAssertEqual(dismissed, 1); XCTAssertEqual(written, 0)
        XCTAssertEqual(outcomes, [.cancelled]); XCTAssertFalse(controller.isPresenting)
    }
    @MainActor func testProtectionAtStartAndWhileDialogOpenPreventsWriting() throws {
        var allowed = false, presented = 0, written = 0
        var reply: ((URL?) -> Void)?
        let controller = ScreenshotSaveAsController(allowed: { allowed }, choose: { _, callback in
            presented += 1; reply = callback; return {}
        }, write: { _, _ in written += 1 })
        controller.present(image: try image(), format: .png) { XCTAssertEqual($0, .cancelled) }
        XCTAssertEqual(presented, 0)
        allowed = true
        controller.present(image: try image(), format: .png) { XCTAssertEqual($0, .cancelled) }
        allowed = false; reply?(URL(fileURLWithPath: "/synthetic.png"))
        XCTAssertEqual(written, 0); XCTAssertFalse(controller.isPresenting)
    }
    @MainActor func testSaveFormatCancelAndFailurePermitRetry() throws {
        var reply: ((URL?) -> Void)?
        var formats: [ScreenshotSettings.Format] = []
        var written: [Data] = []
        var fail = true
        let controller = ScreenshotSaveAsController(allowed: { true }, choose: { format, callback in
            formats.append(format); reply = callback; return {}
        }, write: { data, _ in
            if fail { throw CocoaError(.fileWriteNoPermission) }
            written.append(data)
        })
        controller.present(image: try image(), format: .png) { XCTAssertEqual($0, .cancelled) }
        reply?(nil)
        controller.present(image: try image(), format: .png) { XCTAssertEqual($0, .failed) }
        reply?(URL(fileURLWithPath: "/synthetic.png"))
        fail = false
        controller.present(image: try image(), format: .jpeg) { XCTAssertEqual($0, .saved) }
        reply?(URL(fileURLWithPath: "/synthetic.jpg"))
        XCTAssertEqual(formats, [.png, .png, .jpeg])
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written.first?.prefix(2), Data([0xff, 0xd8]))
        XCTAssertFalse(controller.isPresenting)
    }
}

extension SaveAsTests {
    @MainActor func testSynchronousChooserWritesRealPNGAndDoesNotRetainDismissal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("synthetic.png")
        var dismissals = 0
        let controller = ScreenshotSaveAsController(allowed: { true }, choose: { _, reply in
            reply(url); return { dismissals += 1 }
        })
        controller.present(image: try image(), format: .png) { XCTAssertEqual($0, .saved) }
        XCTAssertFalse(controller.isPresenting)
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(bytes.prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
        XCTAssertEqual(try XCTUnwrap(NSBitmapImageRep(data: bytes)).pixelsWide, 30)
        controller.cancel(); XCTAssertEqual(dismissals, 0)
    }
}

extension SaveAsTests {
    @MainActor func testCoordinatorLetsSavePanelOwnEscapeAndRejectsReplyAfterCancel() throws {
        var reply: ((URL?) -> Void)?
        var writes = 0
        let save = ScreenshotSaveAsController(allowed: { true }, choose: { _, callback in reply = callback; return {} },
            write: { _, _ in writes += 1 })
        let coordinator = ScreenshotCoordinator(allowed: { true }, saveAs: save)
        let image = try image()
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 30, height: 30), image: image)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        coordinator.saveSelection(image, canvas: canvas, displayID: 1)
        XCTAssertNotNil(coordinator.routeCanvasEvent(escape), "The save panel must receive Escape before capture cancellation")
        let right = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertNotNil(coordinator.routeCanvasEvent(right), "The save panel also owns context-menu gestures")
        XCTAssertTrue(save.isPresenting)
        reply?(nil)
        XCTAssertFalse(save.isPresenting)
        coordinator.saveSelection(image, canvas: canvas, displayID: 1)
        coordinator.cancel()
        reply?(URL(fileURLWithPath: "/synthetic.png"))
        XCTAssertEqual(writes, 0)
        XCTAssertNil(coordinator.routeCanvasEvent(escape))
    }
}
