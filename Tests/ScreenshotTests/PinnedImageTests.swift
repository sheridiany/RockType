import XCTest
import AppKit
@testable import RoarkTApp

final class PinnedImageTests: XCTestCase {
    func testZoomLimitsAndOffscreenPlacement() {
        XCTAssertEqual(PinnedImageGeometry.scale(0), 0.1)
        XCTAssertEqual(PinnedImageGeometry.scale(100), 4)
        XCTAssertEqual(PinnedImageGeometry.scale(.nan), 1)
        let screen = CGRect(x: -1200, y: 40, width: 1200, height: 800)
        let original = CGRect(x: -100, y: 700, width: 400, height: 200)
        let fit = PinnedImageGeometry.fitted(original, in: screen)
        XCTAssertTrue(screen.contains(fit))
        XCTAssertEqual(fit.size, original.size)
        let zoom = PinnedImageGeometry.zoom(fit, base: original.size, scale: 100, in: screen)
        XCTAssertTrue(screen.contains(zoom))
        XCTAssertEqual(zoom.width / zoom.height, 2)
        let small = PinnedImageGeometry.zoom(fit, base: original.size, scale: 0, in: screen)
        XCTAssertEqual(small.width, 40); XCTAssertEqual(small.height, 20)
        XCTAssertEqual(small.midX, fit.midX); XCTAssertEqual(small.midY, fit.midY)
    }

    @MainActor func testProtectedPinCreatesNoPanel() throws {
        let controller = PinnedImageController(allowed: { false }, copyImage: { _ in XCTFail("Protected copy") })
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        XCTAssertFalse(controller.pin(try XCTUnwrap(bitmap.cgImage), at: CGRect(x: 0, y: 0, width: 8, height: 4)))
        XCTAssertTrue(controller.panels.isEmpty)
    }
}

extension PinnedImageTests {
    private func syntheticImage(width: Int = 20) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: 10, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 10))
        return try XCTUnwrap(context.makeImage())
    }

    func testHistoryEvictsByCountAndPixelBudget() throws {
        let image = try syntheticImage()
        let entry = PinnedImageHistory.Entry(image: image, frame: CGRect(x: 10, y: 20, width: 20, height: 10), opacity: 0.6, locked: true)
        var countBound = PinnedImageHistory(limit: 2)
        for _ in 0..<3 { countBound.append(entry) }
        XCTAssertEqual(countBound.entries.count, 2)
        var memoryBound = PinnedImageHistory(byteLimit: entry.bytes * 2)
        for _ in 0..<3 { memoryBound.append(entry) }
        XCTAssertEqual(memoryBound.entries.count, 2)
        memoryBound.append(.init(image: try syntheticImage(width: 1000), frame: .zero, opacity: 1, locked: false))
        XCTAssertEqual(memoryBound.entries.count, 2, "Oversized image must not evict useful recent pins")
        memoryBound.clear(); XCTAssertTrue(memoryBound.entries.isEmpty)
    }

    @MainActor func testCloseRestoresStateAndAlwaysExitsPassthrough() throws {
        let controller = PinnedImageController(allowed: { true }, showsMenu: false, present: { _ in })
        defer { controller.closeAll() }
        XCTAssertTrue(controller.pin(try syntheticImage(), at: CGRect(x: 100, y: 100, width: 200, height: 100)))
        let panel = try XCTUnwrap(controller.panels.first)
        let view = try XCTUnwrap(panel.contentView as? PinnedImageView)
        view.toggleLock(); view.togglePassthrough(); panel.alphaValue = 0.6
        XCTAssertFalse(panel.isMovableByWindowBackground)
        XCTAssertTrue(panel.ignoresMouseEvents)
        panel.close()
        XCTAssertTrue(controller.panels.isEmpty)
        XCTAssertEqual(controller.history.entries.count, 1)
        XCTAssertTrue(controller.restoreLast())
        let restored = try XCTUnwrap(controller.panels.first)
        XCTAssertEqual(restored.alphaValue, 0.6)
        XCTAssertFalse(restored.isMovableByWindowBackground)
        XCTAssertFalse(restored.ignoresMouseEvents)
        XCTAssertTrue(controller.history.entries.isEmpty)
        controller.closeAll()
        XCTAssertTrue(controller.panels.isEmpty)
        XCTAssertFalse(controller.restoreLast())
    }

    @MainActor func testPassthroughEscapeAndProtectedHistoryPurge() async throws {
        var allowed = true
        let controller = PinnedImageController(allowed: { allowed }, showsMenu: false, present: { _ in })
        defer { controller.closeAll() }
        XCTAssertTrue(controller.pin(try syntheticImage(), at: CGRect(x: 100, y: 100, width: 20, height: 10)))
        let view = try XCTUnwrap(controller.panels.first?.contentView as? PinnedImageView)
        view.togglePassthrough()
        controller.exitMousePassthrough()
        XCTAssertFalse(try XCTUnwrap(controller.panels.first).ignoresMouseEvents)
        controller.panels.first?.close()
        XCTAssertEqual(controller.history.entries.count, 1)
        allowed = false
        XCTAssertFalse(controller.restoreLast())
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(controller.history.entries.isEmpty)
    }

    @MainActor func testShiftCCopiesTextNotImageAndLockBlocksZoom() throws {
        var copies = 0
        var actions: [PinnedImageAction] = []
        let controller = PinnedImageController(allowed: { true }, copyImage: { _ in copies += 1 }, showsMenu: false, present: { _ in })
        controller.onAction = { _, action in actions.append(action) }
        defer { controller.closeAll() }
        XCTAssertTrue(controller.pin(try syntheticImage(), at: CGRect(x: 100, y: 100, width: 200, height: 100)))
        let panel = try XCTUnwrap(controller.panels.first)
        let view = try XCTUnwrap(panel.contentView as? PinnedImageView)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
            timestamp: 0, windowNumber: 0, context: nil, characters: "C", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertEqual(actions, [.copyText]); XCTAssertEqual(copies, 0)
        view.toggleLock(); let frame = panel.frame
        let scroll = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0))
        view.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: scroll)))
        XCTAssertEqual(panel.frame, frame)
        scroll.flags = .maskAlternate
        view.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: scroll)))
        XCTAssertEqual(panel.frame, frame)
        XCTAssertGreaterThanOrEqual(panel.alphaValue, 0.2)
        XCTAssertEqual(PinnedImageView.opacity(-10), 0.2)
        XCTAssertEqual(PinnedImageView.opacity(2), 1)
        XCTAssertEqual(PinnedImageView.opacity(.nan), 1)
    }
}

extension PinnedImageTests {
    @MainActor func testContextMenuRoutesImageActionsAndOpacity() throws {
        var actions: [PinnedImageAction] = []
        let controller = PinnedImageController(allowed: { true }, showsMenu: false, present: { _ in })
        controller.onAction = { image, action in
            XCTAssertEqual(image.width, 20); XCTAssertEqual(image.height, 10)
            actions.append(action)
        }
        defer { controller.closeAll() }
        XCTAssertTrue(controller.pin(try syntheticImage(), at: CGRect(x: 100, y: 100, width: 200, height: 100)))
        let panel = try XCTUnwrap(controller.panels.first)
        let view = try XCTUnwrap(panel.contentView as? PinnedImageView)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(view.menu(for: event))
        for title in ["另存为…", "识别文字…", "翻译…（先核对识别文字）", "覆盖式图片翻译…", "识别二维码 / 条码…"] {
            let item = try XCTUnwrap(menu.items.first { $0.title == title })
            XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        }
        XCTAssertEqual(actions, [.save, .ocr, .translate, .translateImage, .barcodes])
        let opacity = try XCTUnwrap(menu.items.first { $0.submenu != nil }?.submenu?.items.first { $0.tag == 40 })
        XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(opacity.action), to: opacity.target, from: opacity))
        XCTAssertEqual(panel.alphaValue, 0.4)
    }
}

extension PinnedImageTests {
    func testChangingHistoryLimitImmediatelyEvictsOldestAndZeroStopsRetention() throws {
        let image = try syntheticImage()
        var history = PinnedImageHistory()
        for n in 0..<4 {
            history.append(.init(image: image, frame: CGRect(x: n * 10, y: 0, width: 20, height: 10), opacity: 1, locked: false))
        }
        history.setLimit(2)
        XCTAssertEqual(history.entries.map(\.frame.minX), [20, 30])
        let retained = try XCTUnwrap(history.entries.last)
        history.setLimit(0)
        history.append(retained)
        XCTAssertTrue(history.entries.isEmpty)
        history.setLimit(1000)
        XCTAssertEqual(history.limit, 50)
        history.setLimit(-1)
        XCTAssertEqual(history.limit, 0)
    }
}

extension PinnedImageTests {
    @MainActor func testGroupHideShowFocusWrapAndClosePreservesRecovery() throws {
        var focused: [NSPanel] = [], shown: [NSPanel] = []
        let controller = PinnedImageController(allowed: { true }, showsMenu: false, show: { shown.append($0) }, present: { focused.append($0) })
        defer { controller.closeAll() }
        for _ in 0..<3 { XCTAssertTrue(controller.pin(try syntheticImage(), at: CGRect(x: 100, y: 100, width: 200, height: 100))) }
        let panels = controller.panels, first = try XCTUnwrap(panels.first)
        first.alphaValue = 0.4; first.ignoresMouseEvents = true
        let view = try XCTUnwrap(first.contentView as? PinnedImageView); view.toggleLock()
        controller.toggleAll(); XCTAssertTrue(controller.allHidden); XCTAssertEqual(controller.panels.count, 3)
        XCTAssertTrue(controller.history.entries.isEmpty)
        controller.toggleAll(); XCTAssertFalse(controller.allHidden); XCTAssertEqual(shown.count, 3)
        XCTAssertEqual(first.alphaValue, 0.4); XCTAssertTrue(view.locked); XCTAssertTrue(first.ignoresMouseEvents)
        for expected in panels { controller.focusNext(); XCTAssertTrue(focused.last === expected) }
        controller.focusNext(); XCTAssertTrue(focused.last === first); XCTAssertFalse(first.ignoresMouseEvents)
        controller.toggleAll(); controller.focusNext(); XCTAssertFalse(controller.allHidden)
        controller.closeGroup(); XCTAssertTrue(controller.panels.isEmpty); XCTAssertEqual(controller.history.entries.count, 3)
        XCTAssertTrue(controller.restoreLast()); XCTAssertEqual(controller.panels.count, 1)
    }
    @MainActor func testProtectedGroupActionsNeverShowOrFocusAndPurgeHistory() throws {
        let gate = PinGroupGate()
        var shows = 0, focus = 0
        let controller = PinnedImageController(allowed: { gate.allowed }, showsMenu: false, show: { _ in shows += 1 }, present: { _ in focus += 1 })
        defer { controller.closeAll() }
        XCTAssertTrue(controller.pin(try syntheticImage(), at: CGRect(x: 100, y: 100, width: 20, height: 10)))
        controller.toggleAll(); gate.allowed = false; controller.focusNext(); controller.showAll()
        XCTAssertEqual(shows, 0); XCTAssertEqual(focus, 1)
        XCTAssertTrue(controller.panels.isEmpty); XCTAssertTrue(controller.history.entries.isEmpty); XCTAssertFalse(controller.allHidden)
    }
}
@MainActor private final class PinGroupGate { var allowed = true }
