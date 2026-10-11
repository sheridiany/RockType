import XCTest
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
