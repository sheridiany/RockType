import AppKit
import Testing
import RoarkTPlatform
@testable import RoarkTApp

@MainActor private func destination(_ post: @escaping () throws -> Void, valid: @escaping () -> Bool = { true }, deadline: Double = 100) -> VoicePasteTarget {
    VoicePasteTarget(applicationID: "synthetic.editor", deadline: deadline, validate: valid, post: post)
}

@MainActor @Test func voicePasteRestoresEveryClipboardTypeAndConsumesDestinationOnce() async throws {
    let board = NSPasteboard(name: .init("voice-test-\(UUID())")); defer { board.releaseGlobally() }
    let item = NSPasteboardItem(); item.setString("original synthetic", forType: .string)
    item.setData(Data([1, 2, 3]), forType: .init("test.synthetic-binary"))
    let second = NSPasteboardItem(); second.setData(Data("{\\rtf1\\ansi synthetic}".utf8), forType: .rtf)
    board.writeObjects([item, second])
    let access = ReplacementPasteTransaction.ClipboardAccess.system(board, readable: { true })
    let original = try access.save()
    var posts = 0
    let target = destination {
        #expect(board.string(forType: .string) == "合成语音。")
        posts += 1
    }
    let bridge = VoicePasteBridge(transaction: .init(clipboard: access), captureFocus: { _ in target }, now: { 1 }, settle: {})
    #expect(try await bridge.paste("合成语音。", target: target, allowed: { true }))
    #expect(try access.save() == original)
    #expect(try await !bridge.paste("不能重复。", target: target, allowed: { true }))
    #expect(posts == 1)
}

@MainActor @Test func voicePastePreservesANewCopyDuringDelivery() async throws {
    let board = NSPasteboard(name: .init("voice-test-\(UUID())")); defer { board.releaseGlobally() }
    board.setString("original", forType: .string)
    let access = ReplacementPasteTransaction.ClipboardAccess.system(board, readable: { true })
    let bridge = VoicePasteBridge(transaction: .init(clipboard: access), now: { 1 }, settle: {
        board.clearContents(); board.setString("new synthetic copy", forType: .string)
    })
    #expect(try await bridge.paste("合成语音。", target: destination({}), allowed: { true }))
    #expect(board.string(forType: .string) == "new synthetic copy")
}

@MainActor @Test func voicePasteRechecksProtectionAndFocusAfterClipboardWrite() async throws {
    for protect in [true, false] {
        let board = NSPasteboard(name: .init("voice-test-\(UUID())")); defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        var allowed = true; var focused = true; var posts = 0
        var access = ReplacementPasteTransaction.ClipboardAccess.system(board, readable: { allowed })
        let write = access.write
        access.write = { text, token in
            let count = try write(text, token)
            if protect { allowed = false } else { focused = false }
            return count
        }
        let bridge = VoicePasteBridge(transaction: .init(clipboard: access), now: { 1 }, settle: {})
        do {
            _ = try await bridge.paste("合成语音。", target: destination({ posts += 1 }, valid: { focused }), allowed: { allowed })
            Issue.record("A changed/protected destination must not receive paste")
        } catch { }
        #expect(posts == 0)
        #expect(board.string(forType: .string) == "original")
    }
}

@MainActor @Test func voicePasteRejectsExpiryControlsAndOversizeBeforeClipboardAccess() async throws {
    var snapshots = 0
    let access = ReplacementPasteTransaction.ClipboardAccess(count: { 0 }, save: { snapshots += 1; return ClipboardSnapshot(items: []) },
        write: { _, _ in Issue.record("must not write"); return 0 }, owns: { _, _ in false }, empty: { _ in true }, restore: { _, _ in false })
    let bridge = VoicePasteBridge(transaction: .init(clipboard: access), now: { 100 }, settle: {})
    for (text, expiry) in [("合成语音。", 100.0), ("line\ncommand", 200), ("tab\tcommand", 200), (String(repeating: "x", count: 32_769), 200)] {
        #expect(try await !bridge.paste(text, target: destination({ Issue.record("must not post") }, deadline: expiry), allowed: { true }))
    }
    #expect(snapshots == 0)
}

@MainActor @Test func voicePasteCancellationAfterPostWaitsBeforeRestoring() async throws {
    let board = NSPasteboard(name: .init("voice-test-\(UUID())")); defer { board.releaseGlobally() }
    board.setString("original", forType: .string)
    let transaction = ReplacementPasteTransaction(clipboard: .system(board, readable: { true }))
    var resume: CheckedContinuation<Void, Never>?
    let bridge = VoicePasteBridge(transaction: transaction, now: { 1 }, settle: {
        await withCheckedContinuation { resume = $0 }
    })
    let task = Task { try await bridge.paste("合成语音。", target: destination({}), allowed: { true }) }
    for _ in 0..<100 where resume == nil { await Task.yield() }
    #expect(resume != nil)
    task.cancel()
    #expect(board.string(forType: .string) == "合成语音。" && transaction.busy)
    resume?.resume(); resume = nil
    do { _ = try await task.value; Issue.record("cancelled request must not report success") }
    catch is CancellationError { } catch { Issue.record("unexpected cancellation error") }
    #expect(board.string(forType: .string) == "original" && !transaction.busy)
}
