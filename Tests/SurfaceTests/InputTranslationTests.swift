import AppKit
import SwiftUI
import Testing
import RoarkTCore
import RoarkTPlatform
@testable import RoarkTApp

@MainActor private final class PasteMemory {
    var snapshot = ClipboardSnapshot(items: [["synthetic/type": Data([1, 2])], ["synthetic/other": Data([3])]])
    var count = 0
    var token: UUID?
    var failWrite = false
    var writeHook: () -> Void = {}
    var restores = 0
    var access: ReplacementPasteTransaction.ClipboardAccess {
        .init(count: { self.count }, save: { self.snapshot }, write: { text, token in
            self.count += 1; self.snapshot = .init(items: []); self.token = nil
            if self.failWrite { throw PlatformReadError.writeFailed }
            self.snapshot = .init(items: [["public.utf8-plain-text": Data(text.utf8)]])
            self.token = token; self.writeHook(); return self.count
        }, owns: { self.token == $0 && self.count == $1 }, empty: { self.count == $0 && self.snapshot.items.isEmpty }, restore: { saved, count in
            guard self.count == count else { return false }
            self.restores += 1; self.snapshot = saved; self.token = nil; self.count += 1; return true
        })
    }
    func userCopy() { count += 1; token = nil; snapshot = .init(items: [["user": Data([9])]]) }
}

@MainActor private final class InputTestRunner: OperationRunner {
    var requests: [OperationRequest] = []
    func start() {}; func stop() {}; func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> { requests.append(request); return AsyncStream { _ in } }
}

@Suite(.serialized) @MainActor struct InputTranslationTests {
    @Test func pasteRestoresEveryTypeButNeverOverwritesANewerCopy() async throws {
        let memory = PasteMemory(), original = PasteMemory().snapshot
        let transaction = ReplacementPasteTransaction(clipboard: memory.access)
        var posts = 0
        let restored = try await transaction.paste("Synthetic result", allowed: { true }, validate: { true }, post: { posts += 1 }, settle: {})
        #expect(restored && memory.snapshot == original && posts == 1)
        let newer = try await transaction.paste("Synthetic result", allowed: { true }, validate: { true }, post: { posts += 1 }, settle: { memory.userCopy() })
        #expect(!newer && memory.snapshot.items.first?["user"] == Data([9]) && memory.restores == 1)
    }
    @Test func copyDuringSnapshotRemainsOwnedByTheUser() async throws {
        let memory = PasteMemory()
        var access = memory.access
        access.save = { let old = memory.snapshot; memory.userCopy(); return old }
        let transaction = ReplacementPasteTransaction(clipboard: access)
        do {
            _ = try await transaction.paste("Synthetic", allowed: { true }, validate: { true }, post: { Issue.record("Stale clipboard pasted") }, settle: {})
            Issue.record("Clipboard race accepted")
        } catch { #expect(error as? PlatformReadError == .clipboardChanged) }
        #expect(memory.snapshot.items.first?["user"] == Data([9]) && memory.restores == 0)
    }
    @Test func protectionAndSourceChangesCannotPostAndFailedWritesRestore() async throws {
        let memory = PasteMemory(), original = PasteMemory().snapshot
        let transaction = ReplacementPasteTransaction(clipboard: memory.access)
        var allowed = true, posts = 0
        memory.writeHook = { allowed = false }
        do {
            _ = try await transaction.paste("Synthetic", allowed: { allowed }, validate: { true }, post: { posts += 1 }, settle: {})
            Issue.record("Protected paste accepted")
        } catch { }
        #expect(posts == 0 && memory.snapshot == original)
        memory.writeHook = {}; memory.failWrite = true; allowed = true
        do { _ = try await transaction.paste("Synthetic", allowed: { true }, validate: { true }, post: { posts += 1 }, settle: {}); Issue.record("Failed write accepted") } catch {}
        #expect(posts == 0 && memory.snapshot == original)
        memory.failWrite = false
        do { _ = try await transaction.paste("Synthetic", allowed: { true }, validate: { false }, post: { posts += 1 }, settle: {}); Issue.record("Changed source accepted") } catch {}
        #expect(posts == 0 && memory.snapshot == original)
    }
    @Test func cancellationAfterPostingWaitsForPasteBeforeRestoringAndExcludesConcurrentWrites() async throws {
        let memory = PasteMemory(), original = PasteMemory().snapshot
        let transaction = ReplacementPasteTransaction(clipboard: memory.access)
        var release: CheckedContinuation<Void, Never>?
        let task = Task { try await transaction.paste("Synthetic", allowed: { true }, validate: { true }, post: {}, settle: {
            await withCheckedContinuation { release = $0 }
        }) }
        for _ in 0..<1000 where release == nil { await Task.yield() }
        try #require(release != nil)
        task.cancel()
        #expect(memory.snapshot != original && transaction.busy)
        do { _ = try await transaction.paste("Concurrent", allowed: { true }, validate: { true }, post: {}, settle: {}); Issue.record("Concurrent paste accepted") }
        catch { #expect(error as? PlatformReadError == .busy) }
        release?.resume()
        do { _ = try await task.value; Issue.record("Cancelled transaction succeeded") } catch is CancellationError {}
        #expect(memory.snapshot == original && !transaction.busy)
    }
    @Test func isolatedSystemPasteboardPreservesBinaryTypesAndEmptyClipboard() async throws {
        let board = NSPasteboard(name: .init("synthetic-replacement-\(UUID())"))
        defer { board.releaseGlobally() }
        let first = NSPasteboardItem(), second = NSPasteboardItem()
        first.setData(Data([0, 255, 1]), forType: .init("synthetic.binary")); first.setString("Synthetic", forType: .string)
        second.setData(Data([3, 4]), forType: .init("synthetic.second"))
        board.writeObjects([first, second])
        let access = ReplacementPasteTransaction.ClipboardAccess.system(board, readable: { true })
        let saved = try access.save()
        let transaction = ReplacementPasteTransaction(clipboard: access)
        #expect(try await transaction.paste("Synthetic result", allowed: { true }, validate: { true }, post: {}, settle: {}))
        #expect(try access.save() == saved)
        board.clearContents()
        #expect(try await transaction.paste("Synthetic result", allowed: { true }, validate: { true }, post: {}, settle: {}))
        #expect((board.pasteboardItems ?? []).isEmpty)
    }
    @Test func shortcutCaptureFailureFallsBackOnlyForTranslationAndNeverForProtectedInput() async throws {
        let source = ContentSnapshot.Source(pid: 42, bundleID: "synthetic.editor", applicationName: "Synthetic")
        var front = source
        var status: SelectionReader.Status = .empty, allowed = true, openings: [String] = [], notices: [String] = []
        let capture = SelectionCapture(allowed: { allowed }, context: { .init(source: source, isCurrent: { true }) },
            read: { .init(status: status, text: nil, rect: nil) }, copy: { nil })
        let controller = SelectionController(settings: { .defaults }, perform: { _, _, _ in Issue.record("Empty request sent") }, search: { _, _ in },
            notice: { notices.append($0) }, allowed: { allowed }, capture: capture, frontmost: { front })
        controller.inputTranslation = { openings.append($0) }; controller.start(); defer { controller.stop() }
        controller.trigger(.translateSelection)
        for _ in 0..<1000 where openings.count < 1 { await Task.yield() }
        #expect(openings == ["translate"])
        status = .unsupported; controller.trigger(.translateSelection)
        for _ in 0..<1000 where openings.count < 2 { await Task.yield() }
        #expect(openings.count == 2)
        status = .secureInput; controller.trigger(.translateSelection)
        for _ in 0..<30 { await Task.yield() }
        #expect(openings.count == 2)
        status = .empty; controller.trigger(.summarizeSelection)
        for _ in 0..<30 { await Task.yield() }
        #expect(openings.count == 2 && !notices.isEmpty)
        front = .init(pid: 42, bundleID: "com.apple.finder", applicationName: "Synthetic")
        controller.trigger(.translateSelection)
        #expect(openings.count == 3)
        front = .init(pid: ProcessInfo.processInfo.processIdentifier, bundleID: Identifiers.appBundleID, applicationName: "Synthetic")
        controller.trigger(.translateSelection)
        #expect(openings.count == 4)
        #expect(TranslateWindowState.accepts(.init(name: "日语翻译", icon: "character.bubble", prompt: "Translate to Japanese.")))
        allowed = false; controller.trigger(.translateSelection)
        #expect(openings.count == 4)
    }
    @Test func inputEntryFocusesEmptyEditorWithoutSendingAndHonorsProtection() throws {
        _ = NSApplication.shared
        let runner = InputTestRunner(); var allowed = true
        let environment = OperationsEnvironment()
        let controller = SelectionOperationsController(environment: environment, settings: { .defaults }, aiConfigured: { true }, notice: { _ in }, readable: { allowed }, makeRunner: { runner })
        defer { controller.stop() }
        controller.openInputTranslation()
        #expect(controller.translationWindow?.isVisible == true && controller.translationWindow?.state.original.isEmpty == true)
        #expect(runner.requests.isEmpty)
        #expect(controller.translationWindow?.isSourceFocused == true)
        controller.clearCurrentContent()
        let snapshot = ContentSnapshot(text: "Synthetic", source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)
        controller.perform(.init(session: .init(snapshot: snapshot), template: OperationTemplate.defaults[2], settings: .defaults), source: nil, toolbarRect: nil)
        #expect(controller.window?.sourceReplacement != nil)
        #expect(controller.window?.sourceReplacement?.unavailableReason != nil)
        let count = runner.requests.count
        controller.clearCurrentContent(); allowed = false; controller.openInputTranslation()
        #expect(controller.translationWindow == nil && runner.requests.count == count)
    }
    @Test func renderEmptyAndReplacementAvailability() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/t3")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            for mode in ["empty", "replace", "unavailable"] {
                let snapshot = ContentSnapshot(text: mode == "empty" ? "" : "Make each change easy to review.", source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)
                let request = OperationRequest(session: .init(snapshot: snapshot), template: OperationTemplate.defaults[0], settings: .defaults)
                let state = TranslateWindowState(request: request, runner: InputTestRunner(), settings: { .defaults }, allowed: { true })
                if mode != "empty" { state.showCompleted(.init(session: .init(snapshot: snapshot), templateID: "translate", text: "让每项修改都便于审阅。", engine: "synthetic-model")) }
                let replacement = SourceReplacement(previewReason: mode == "replace" ? nil : "来源应用已切换，请重新划词后替换。")
                var slots = TranslateWindowSlots()
                slots.replacement = { AnyView(SourceReplacementButton(replacement: replacement, text: state.result.answer, feedback: { _ in })) }
                let hosting = NSHostingView(rootView: TranslateWindowView(state: state, close: {}, focusEditor: {}, copy: { _, _ in }, slots: slots)
                    .environment(\.colorScheme, dark ? .dark : .light).frame(width: 420, height: 380))
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 380), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = hosting
                hosting.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)); hosting.displayIfNeeded()
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)); hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("input-\(mode)-\(dark ? "dark" : "light").png"))
                window.close(); state.stop()
            }
        }
    }
}
