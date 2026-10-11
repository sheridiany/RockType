import AppKit
import Darwin
import XCTest
import SwiftUI
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class HistoryGate { var allowed = true; var date = Date(timeIntervalSince1970: 1_800_000_000) }
@MainActor private final class HistoryOCR {
    var replies: [CheckedContinuation<String, Never>] = []
    func run() async -> String { await withCheckedContinuation { replies.append($0) } }
}

final class ScreenshotHistoryTests: XCTestCase {
    private func temporary() -> URL {
        let path = FileManager.default.temporaryDirectory.path
        let resolved = realpath(path, nil); defer { free(resolved) }
        return URL(fileURLWithPath: resolved.map { String(cString: $0) } ?? path).appendingPathComponent(UUID().uuidString)
    }
    private func image(_ width: Int = 64) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: 32))
        return try XCTUnwrap(context.makeImage())
    }
    @MainActor func testMemoryDefaultsBoundSearchProtectionAndNoFiles() async throws {
        let folder = temporary(), gate = HistoryGate(), picture = try image()
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { gate.allowed }, now: { gate.date }, recognize: { _, _ in "" })
        history.start(.init()); defer { history.stop(); try? FileManager.default.removeItem(at: folder) }
        var ids: [UUID] = []
        for index in 0..<23 {
            gate.date += 1; let id = try XCTUnwrap(history.record(picture)); ids.append(id)
            history.updateText("合成图 \(index) SwiftUI", id: id)
        }
        XCTAssertEqual(history.entries.count, 20)
        XCTAssertEqual(history.entries.first?.id, ids.last); XCTAssertEqual(history.entries.last?.id, ids[3])
        XCTAssertEqual(history.matches("图 10 swiftui").map(\.id), [ids[10]])
        gate.allowed = false
        XCTAssertNil(history.record(picture)); history.updateText("blocked", id: ids[10])
        XCTAssertEqual(history.matches("图 10 swiftui").count, 1)
        await history.flush(); XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        history.stop(); XCTAssertTrue(history.entries.isEmpty)
    }
    @MainActor func testOptInRoundTripRetentionDeleteClearAndDisable() async throws {
        let folder = temporary(), gate = HistoryGate(), picture = try image()
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = ScreenshotHistoryDisk(folder: folder)
        var settings = ScreenshotSettings(); settings.historyOnDisk = true; settings.historyDiskCount = 3; settings.historyDiskDays = 2
        let first = ScreenshotHistory(disk: archive, allowed: { gate.allowed }, now: { gate.date }, recognize: { _, _ in "" })
        first.start(settings); await first.flush()
        for number in 0..<4 { gate.date += 1; let id = try XCTUnwrap(first.record(picture)); first.updateText("cached \(number)", id: id) }
        await first.flush(); XCTAssertEqual(first.entries.count, 3); XCTAssertNil(first.notice)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.json").path))
        let expected = first.entries.map(\.id); first.stop()
        // A new archive actor emulates a fresh process, including the revision counter.
        let second = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { gate.allowed }, now: { gate.date }, recognize: { _, _ in "" })
        second.start(settings); await second.flush(); defer { second.stop() }
        XCTAssertEqual(second.entries.map(\.id), expected)
        XCTAssertEqual(second.matches("cached 2").count, 1)
        let oldest = try XCTUnwrap(second.entries.last); second.remove(oldest.id); await second.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(oldest.id.uuidString + ".png").path))
        settings.historyDiskCount = 1; second.configure(settings); await second.flush(); XCTAssertEqual(second.entries.count, 1)
        gate.date += 3 * 86400; second.prune(); await second.flush()
        XCTAssertTrue(second.entries.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        _ = second.record(picture); await second.flush()
        settings.historyOnDisk = false; second.configure(settings); await second.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path)); XCTAssertEqual(second.entries.count, 1)
        settings.historyOnDisk = true; second.configure(settings); await second.flush()
        second.clear(); await second.flush()
        XCTAssertTrue(second.entries.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
    @MainActor func testClearWhileLoadingAndPendingWriteDoesNotRestoreFiles() async throws {
        let folder = temporary(), picture = try image(); defer { try? FileManager.default.removeItem(at: folder) }
        let disk = ScreenshotHistoryDisk(folder: folder)
        try await disk.write([.init(date: Date(), image: picture, text: "old")], revision: 1, enabled: true, allowed: { true })
        var settings = ScreenshotSettings(); settings.historyOnDisk = true
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { true }, recognize: { _, _ in "" })
        history.start(settings); history.clear(); await history.flush()
        XCTAssertTrue(history.entries.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        _ = history.record(picture); history.clear(); await history.flush()
        XCTAssertTrue(history.entries.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        history.stop()
    }
    @MainActor func testAutomaticOCRNeverOverwritesEditsOrResurrectsClearedOrProtectedHistory() async throws {
        let folder = temporary(), gate = HistoryGate(), ocr = HistoryOCR(), picture = try image()
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { gate.allowed }, recognize: { _, _ in await ocr.run() })
        history.start(.init()); defer { history.stop() }
        let first = try XCTUnwrap(history.record(picture))
        await OverlayTranslationTests.settle { ocr.replies.count == 1 }
        history.updateText("edited", id: first); try XCTUnwrap(ocr.replies.first).resume(returning: "obsolete OCR")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(history.entries.first?.text, "edited")
        _ = history.record(picture); await OverlayTranslationTests.settle { ocr.replies.count == 2 }
        history.clear(); try XCTUnwrap(ocr.replies.dropFirst().first).resume(returning: "late OCR")
        for _ in 0..<10 { await Task.yield() }; XCTAssertTrue(history.entries.isEmpty)
        _ = history.record(picture); await OverlayTranslationTests.settle { ocr.replies.count == 3 }
        gate.allowed = false; try XCTUnwrap(ocr.replies.dropFirst(2).first).resume(returning: "protected OCR")
        for _ in 0..<10 { await Task.yield() }; XCTAssertEqual(history.entries.first?.text, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
    @MainActor func testProductionOCRCreatesSearchableCache() async throws {
        let folder = temporary()
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { true })
        history.start(.init()); defer { history.stop() }
        _ = history.record(try OverlayTranslationTests.image())
        await OverlayTranslationTests.settle { history.entries.first?.text.isEmpty == false }
        XCTAssertFalse(history.entries.first?.text.isEmpty ?? true)
        XCTAssertEqual(history.matches("Hello").count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
    @MainActor func testDiskRefusesLinksAndProtectionBeforeWriting() async throws {
        let root = temporary(), folder = root.appendingPathComponent("history"), target = root.appendingPathComponent("outside")
        let fm = FileManager.default; defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("preserve".utf8).write(to: target.appendingPathComponent("sentinel"))
        let entries = [ScreenshotHistoryEntry(date: Date(), image: try image(), text: "synthetic")]
        let protected = ScreenshotHistoryDisk(folder: folder)
        do { try await protected.write(entries, revision: 1, enabled: true, allowed: { false }); XCTFail("Expected protection") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertFalse(fm.fileExists(atPath: folder.path))
        try fm.createSymbolicLink(at: folder, withDestinationURL: target)
        do { try await protected.write(entries, revision: 2, enabled: true, allowed: { true }); XCTFail("Expected link rejection") } catch {}
        do { try await protected.write([], revision: 3, enabled: false, allowed: { true }); XCTFail("Expected link rejection") } catch {}
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("sentinel")), Data("preserve".utf8))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: target.path), ["sentinel"])
    }
    @MainActor func testReopenBindsEditedCacheWithoutDuplicateAndCloseDoesNotEraseCache() async throws {
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: temporary()), allowed: { true }, recognize: { _, _ in "" })
        let coordinator = ScreenshotCoordinator(allowed: { true }, history: history, presentPreview: { _ in })
        coordinator.start(); defer { coordinator.stop() }
        let id = try XCTUnwrap(history.record(try image())); history.updateText("cached", id: id)
        coordinator.openHistory(try XCTUnwrap(history.entries.first))
        XCTAssertEqual(coordinator.session?.text, "cached"); XCTAssertEqual(history.entries.count, 1)
        coordinator.session?.text = "corrected"; coordinator.closePreview()
        XCTAssertEqual(history.entries.first?.text, "corrected")
        history.remove(id); coordinator.openImage(try image(), origin: "synthetic", historyID: id)
        coordinator.session?.text = "late"; XCTAssertTrue(history.entries.isEmpty)
    }
    @MainActor func testHistoryPanelClosesOnProtectionAndRendersBothThemes() async throws {
        let folder = temporary(), gate = HistoryGate()
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { gate.allowed }, recognize: { _, _ in "" })
        history.start(.init()); defer { history.stop() }
        for index in 0..<3 { let id = try XCTUnwrap(history.record(try image(64 + index * 32))); history.updateText("合成截图 \(index) · SwiftUI", id: id) }
        let controller = ScreenshotHistoryPanelController(history: history, allowed: { gate.allowed }, open: { _ in }, action: { _, _ in }, present: { _ in })
        controller.show(); XCTAssertNotNil(controller.panel)
        gate.allowed = false; await OverlayTranslationTests.settle { controller.panel == nil }
        XCTAssertNil(controller.panel); gate.allowed = true
        for empty in [false, true] {
            if empty { history.clear(); await history.flush() }
            for width in [760, 500] { for dark in [false, true] {
            let hosting = NSHostingView(rootView: ScreenshotHistoryView(history: history, open: { _ in }, action: { _, _ in }, close: {}).environment(\.colorScheme, dark ? .dark : .light))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 580), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = hosting
            hosting.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(30))
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])); XCTAssertGreaterThan(data.count, 5000)
            try data.write(to: URL(fileURLWithPath: "/tmp/roarkt-r4-history-\(empty ? "empty" : "populated")-\(width)-\(dark ? "dark" : "light").png"))
            window.contentView = nil; window.close()
            } }
        }
    }
}

extension ScreenshotHistoryTests {
    @MainActor func testSuccessfulSaveEntersHistoryButCancellationAndProtectedReplyDoNot() throws {
        let gate = HistoryGate(), history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: temporary()), allowed: { gate.allowed }, recognize: { _, _ in "" })
        var reply: ((URL?) -> Void)?, writes = 0
        let save = ScreenshotSaveAsController(allowed: { gate.allowed }, choose: { _, completion in reply = completion; return {} }, write: { _, _ in writes += 1 })
        let coordinator = ScreenshotCoordinator(allowed: { gate.allowed }, history: history, saveAs: save, presentPreview: { _ in })
        coordinator.start(); defer { coordinator.stop() }
        let image = try image(), canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 64, height: 32), image: image)
        coordinator.saveSelection(image, canvas: canvas, displayID: 1)
        reply?(nil); XCTAssertTrue(history.entries.isEmpty); XCTAssertEqual(writes, 0)
        coordinator.saveSelection(image, canvas: canvas, displayID: 1)
        reply?(URL(fileURLWithPath: "/synthetic-history-test.png"))
        XCTAssertEqual(history.entries.count, 1); XCTAssertEqual(writes, 1)
        // Saving an existing record must use the same save boundary without adding another record.
        coordinator.historyAction(try XCTUnwrap(history.entries.first), action: .save)
        reply?(URL(fileURLWithPath: "/synthetic-history-export.png"))
        XCTAssertEqual(history.entries.count, 1); XCTAssertEqual(writes, 2)
        coordinator.saveSelection(image, canvas: canvas, displayID: 1); gate.allowed = false
        reply?(URL(fileURLWithPath: "/blocked.png"))
        XCTAssertEqual(history.entries.count, 1); XCTAssertEqual(writes, 2)
    }
    @MainActor func testNewerClearRejectsOldDiskRevision() async throws {
        let folder = temporary()
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = ScreenshotHistoryDisk(folder: folder)
        let entries = [ScreenshotHistoryEntry(date: Date(), image: try image(), text: "synthetic")]
        let waiting = HistoryWriteGate()
        let old = Task { try await disk.write(entries, revision: 1, enabled: true, allowed: { waiting.calls += 1; return true }) }
        // The writer must yield to the main actor for every permission check.
        await OverlayTranslationTests.settle { waiting.calls > 0 }
        old.cancel()
        try await disk.write([], revision: 2, enabled: false, allowed: { true })
        _ = try? await old.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        try await disk.write(entries, revision: 1, enabled: true, allowed: { true })
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
    @MainActor func testProtectedStartupCanResumeWithoutLosingExistingDiskHistory() async throws {
        let folder = temporary(), gate = HistoryGate(); defer { try? FileManager.default.removeItem(at: folder) }
        var entry = ScreenshotHistoryEntry(date: gate.date, image: try image(), text: "kept cache"); entry.recognized = true
        try await ScreenshotHistoryDisk(folder: folder).write([entry], revision: 1, enabled: true, allowed: { true })
        gate.allowed = false
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { gate.allowed }, now: { gate.date }, recognize: { _, _ in "" })
        var settings = ScreenshotSettings(); settings.historyOnDisk = true
        history.start(settings); await history.flush(); defer { history.stop() }
        XCTAssertTrue(history.entries.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        gate.allowed = true; history.refresh(); await history.flush()
        XCTAssertEqual(history.entries.map(\.id), [entry.id]); XCTAssertEqual(history.entries.first?.text, "kept cache")
    }
}
@MainActor private final class HistoryWriteGate { var calls = 0 }

extension ScreenshotHistoryTests {
    @MainActor func testFailedClearRetryDeletesRatherThanReloadingOldRecords() async throws {
        let root = temporary(), folder = root.appendingPathComponent("history"), moved = root.appendingPathComponent("held")
        let fm = FileManager.default; defer { try? fm.removeItem(at: root) }
        var settings = ScreenshotSettings(); settings.historyOnDisk = true
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { true }, recognize: { _, _ in "" })
        history.start(settings); await history.flush(); defer { history.stop() }
        _ = history.record(try image()); await history.flush()
        try fm.moveItem(at: folder, to: moved); try fm.createSymbolicLink(at: folder, withDestinationURL: moved)
        history.clear(); await history.flush()
        XCTAssertNotNil(history.notice); XCTAssertTrue(history.entries.isEmpty)
        try fm.removeItem(at: folder); try fm.moveItem(at: moved, to: folder)
        history.retryDisk(); await history.flush()
        XCTAssertNil(history.notice); XCTAssertTrue(history.entries.isEmpty); XCTAssertFalse(fm.fileExists(atPath: folder.path))
    }
    @MainActor func testRapidOptOutOptInDoesNotReloadEvictedDiskRecords() async throws {
        let folder = temporary(), gate = HistoryGate(); defer { try? FileManager.default.removeItem(at: folder) }
        var settings = ScreenshotSettings(); settings.historyOnDisk = true; settings.historyDiskCount = 25
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { true }, now: { gate.date }, recognize: { _, _ in "" })
        history.start(settings); await history.flush(); defer { history.stop() }
        let picture = try image()
        for _ in 0..<25 { gate.date += 1; _ = history.record(picture) }
        await history.flush(); XCTAssertEqual(history.entries.count, 25)
        settings.historyOnDisk = false; history.configure(settings)
        settings.historyOnDisk = true; history.configure(settings); await history.flush()
        XCTAssertEqual(history.entries.count, 20)
        let disk = ScreenshotHistoryDisk(folder: folder)
        let loaded = try await disk.load(allowed: { true }); XCTAssertEqual(loaded.count, 20)
    }
    @MainActor func testProtectionDelaysDiskSyncThenRefreshSavesIt() async throws {
        let folder = temporary(), gate = HistoryGate(); defer { try? FileManager.default.removeItem(at: folder) }
        var settings = ScreenshotSettings(); settings.historyOnDisk = true
        let history = ScreenshotHistory(disk: ScreenshotHistoryDisk(folder: folder), allowed: { gate.allowed }, now: { gate.date }, recognize: { _, _ in "" })
        history.start(settings); await history.flush(); defer { history.stop() }
        _ = history.record(try image()); gate.allowed = false; await history.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        gate.allowed = true; history.refresh(); await history.flush()
        let loaded = try await ScreenshotHistoryDisk(folder: folder).load(allowed: { true })
        XCTAssertEqual(loaded.count, 1)
    }
}
