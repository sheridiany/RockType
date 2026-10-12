import XCTest
import AppKit
@testable import RoarkTPlatform

@MainActor private final class MemoryClipboard: ClipboardBackend {
    var changeCount = 0
    var content = ClipboardSnapshot(items: [["custom": Data([1, 2]), "public.utf8-plain-text": Data("original".utf8)], ["image": Data([3])]])
    var restores = 0
    var onRead: (() -> Void)?
    func snapshot() -> ClipboardSnapshot { content }
    func restore(_ snapshot: ClipboardSnapshot) { restores += 1; content = snapshot; changeCount += 1 }
    func string() -> String? { onRead?(); return "synthetic selection" }
    func copied() { changeCount += 1; content = ClipboardSnapshot(items: [["copy": Data([4])]]) }
}

final class ClipboardTests: XCTestCase {
    @MainActor func testCopiesAndRestoresEveryTypeAndItem() async throws {
        let board = MemoryClipboard(), original = MemoryClipboard().content
        let clipboard = Clipboard(backend: board, checkReadable: {}, sourcePID: { 1 }, postCopy: { board.copied() })
        let text = try await clipboard.copySelectionFallback()
        XCTAssertEqual(text, "synthetic selection")
        XCTAssertEqual(board.content, original)
        XCTAssertEqual(board.restores, 1)
    }

    @MainActor func testUserCopyWins() async {
        let board = MemoryClipboard()
        let userCopy = ClipboardSnapshot(items: [["user": Data([5])]])
        board.onRead = { board.content = userCopy; board.changeCount += 1 }
        let clipboard = Clipboard(backend: board, checkReadable: {}, sourcePID: { 1 }, postCopy: { board.copied() })
        do { _ = try await clipboard.copySelectionFallback(); XCTFail("Expected changed clipboard") }
        catch { XCTAssertEqual(error as? PlatformReadError, .clipboardChanged) }
        XCTAssertEqual(board.content, userCopy)
        XCTAssertEqual(board.restores, 0)
    }

    @MainActor func testSecureInputDoesNotReadOrPostCopy() async {
        let board = MemoryClipboard()
        let clipboard = Clipboard(backend: board, checkReadable: { throw PlatformReadError.secureInput }, sourcePID: { 1 }, postCopy: { XCTFail("Must not copy") })
        do { _ = try await clipboard.copySelectionFallback(); XCTFail("Must reject") }
        catch { XCTAssertEqual(error as? PlatformReadError, .secureInput) }
        XCTAssertEqual(board.changeCount, 0)
    }

    @MainActor func testTimeoutDoesNotRestore() async {
        let board = MemoryClipboard()
        let clipboard = Clipboard(backend: board, checkReadable: {}, sourcePID: { 1 }, postCopy: {})
        do { _ = try await clipboard.copySelectionFallback(timeout: .zero); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? PlatformReadError, .timeout) }
        XCTAssertEqual(board.restores, 0)
    }

    @MainActor func testSourceChangeDiscardsTextAndRestores() async {
        let board = MemoryClipboard()
        var pid: Int32 = 1
        let clipboard = Clipboard(backend: board, checkReadable: {}, sourcePID: { pid }, postCopy: { board.copied(); pid = 2 })
        do { _ = try await clipboard.copySelectionFallback(); XCTFail("Expected source change") }
        catch { XCTAssertEqual(error as? PlatformReadError, .sourceChanged) }
        XCTAssertEqual(board.restores, 1)
    }

    @MainActor func testCancellationAfterCopyRestores() async {
        let board = MemoryClipboard()
        let clipboard = Clipboard(backend: board, checkReadable: {}, sourcePID: { 1 }, postCopy: { board.copied() })
        let task = Task { try await clipboard.copySelectionFallback() }
        board.onRead = { task.cancel() }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(board.restores, 1)
    }
}

extension ClipboardTests {
    @MainActor func testCancellationWhileWaitingRestoresDelayedCopyWithoutReadingIt() async throws {
        let board = MemoryClipboard(), original = board.content
        var posted = false
        board.onRead = { XCTFail("Cancelled content must not be read") }
        let clipboard = Clipboard(backend: board, checkReadable: {}, sourcePID: { 1 }, postCopy: {
            posted = true
            Task { try await Task.sleep(for: .milliseconds(30)); board.copied() }
        })
        let request = Task { try await clipboard.copySelectionFallback() }
        for _ in 0..<100 where !posted { await Task.yield() }
        XCTAssertTrue(posted)
        request.cancel()
        do { _ = try await request.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        XCTAssertEqual(board.content, original); XCTAssertEqual(board.restores, 1)
    }

    @MainActor func testProtectionDuringDelayedCopyRestoresAndNeverReadsSelection() async throws {
        let board = MemoryClipboard(), original = board.content
        var allowed = true
        board.onRead = { XCTFail("Protected content must not be read") }
        let clipboard = Clipboard(backend: board, checkReadable: {
            if !allowed { throw PlatformReadError.secureInput }
        }, sourcePID: { 1 }, postCopy: {
            allowed = false
            Task { try await Task.sleep(for: .milliseconds(25)); board.copied() }
        })
        do { _ = try await clipboard.copySelectionFallback(); XCTFail("Expected protection") }
        catch { XCTAssertEqual(error as? PlatformReadError, .secureInput) }
        XCTAssertEqual(board.content, original); XCTAssertEqual(board.restores, 1)
    }

    @MainActor func testIsolatedPasteboardRestoresMultipleTypesAndItems() async throws {
        let board = NSPasteboard(name: .init("synthetic-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let backend = SystemClipboard(pasteboard: board)
        let original = ClipboardSnapshot(items: [
            ["public.utf8-plain-text": Data("synthetic".utf8), "public.html": Data("<b>synthetic</b>".utf8),
             "public.rtf": Data("{\\rtf1 synthetic}".utf8)],
            ["public.png": Data([1, 2, 3]), "synthetic.custom": Data([4, 5])]
        ])
        try backend.restore(original)
        let saved = try backend.snapshot()
        let clipboard = Clipboard(backend: backend, checkReadable: {}, sourcePID: { 1 }, postCopy: {
            try backend.restore(.init(items: [["public.utf8-plain-text": Data("selection".utf8)]]))
        })
        let text = try await clipboard.copySelectionFallback()
        XCTAssertEqual(text, "selection")
        XCTAssertEqual(try backend.snapshot(), saved)
        for (index, item) in original.items.enumerated() {
            for (type, data) in item { XCTAssertEqual(try backend.snapshot().items[index][type], data) }
        }
    }
}

extension ClipboardTests {
    @MainActor func testMultipleWritesBeforeObservationDoNotOverwriteNewerClipboard() async throws {
        let board = MemoryClipboard()
        let latest = ClipboardSnapshot(items: [["synthetic.user": Data([7, 8])]])
        board.onRead = { XCTFail("Ambiguous copy must not be read") }
        let clipboard = Clipboard(backend: board, checkReadable: {}, sourcePID: { 1 }, postCopy: {
            board.copied(); board.content = latest; board.changeCount += 1
        })
        do { _ = try await clipboard.copySelectionFallback(); XCTFail("Expected changed clipboard") }
        catch { XCTAssertEqual(error as? PlatformReadError, .clipboardChanged) }
        XCTAssertEqual(board.content, latest); XCTAssertEqual(board.restores, 0)
    }
}

@MainActor private final class DeferredTextClipboard: ClipboardBackend {
    var changeCount = 0
    var ready = false
    var restored = false
    func snapshot() -> ClipboardSnapshot { .init(items: [["custom": Data([1, 2])]]) }
    func restore(_ snapshot: ClipboardSnapshot) { restored = true; changeCount += 1 }
    func string() -> String? { ready ? "synthetic delayed text" : nil }
}
extension ClipboardTests {
    @MainActor func testDelayedPlainTextWithinSameGenerationIsReadAndRestored() async throws {
        let board = DeferredTextClipboard()
        let clipboard = Clipboard(backend: board, checkReadable: {}, sourcePID: { 1 }, postCopy: {
            board.changeCount += 1
            Task { try await Task.sleep(for: .milliseconds(65)); board.ready = true }
        })
        let text = try await clipboard.copySelectionFallback()
        XCTAssertEqual(text, "synthetic delayed text"); XCTAssertTrue(board.restored)
    }
    @MainActor func testMissingPlainTextTimesOutAndRestoresOwnedGeneration() async {
        let board = DeferredTextClipboard()
        let clipboard = Clipboard(backend: board, checkReadable: {}, sourcePID: { 1 }, postCopy: { board.changeCount += 1 })
        do { _ = try await clipboard.copySelectionFallback(timeout: .milliseconds(40)); XCTFail("Must time out") }
        catch { XCTAssertEqual(error as? PlatformReadError, .timeout) }
        XCTAssertTrue(board.restored)
    }
}
