import AppKit
import SwiftUI
import Testing
import Observation
import RoarkTCore
@testable import RoarkTApp

@Test func resultMarkdownPreservesUnfinishedCodeAndRejectsActionLinks() {
    let blocks = ResultMarkdown.blocks("# Title\n\nText **strong**\n\n```swift\nlet x = 1\n  print(x)")
    #expect(blocks.count == 3)
    #expect(blocks[0] == .init(kind: .heading(1), text: "Title"))
    #expect(blocks[2] == .init(kind: .code("swift"), text: "let x = 1\n  print(x)"))
    let closed = ResultMarkdown.blocks("~~~~text\n```\n~~~~\nAfter")
    #expect(closed.first == .init(kind: .code("text"), text: "```"))
    let safe = ResultMarkdown.inline("[file](file:///tmp/test) [action](custom://run) [web](https://example.invalid)")
    #expect(safe.runs.compactMap(\.link).map(\.scheme) == ["https"])
}

@Test @MainActor func rememberedResultGeometrySurvivesReloadAndFitsRemovedDisplay() throws {
    let suite = "test-result-geometry-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let memory = ResultWindowGeometry(defaults: defaults)
    memory.remember(CGRect(x: -1900, y: 150, width: 650, height: 800))
    let reloaded = ResultWindowGeometry(defaults: defaults)
    #expect(reloaded.frame == memory.frame)
    let screen = CGRect(x: 0, y: 0, width: 1280, height: 720)
    let frame = ResultWindowGeometry.fitted(try #require(reloaded.frame), in: screen)
    #expect(screen.contains(frame) && frame.width == 650)
    memory.remember(CGRect(x: 0, y: 0, width: -1, height: 10))
    #expect(memory.frame == reloaded.frame)
}

@MainActor @Observable private final class ScrollProbe {
    var text = String(repeating: "Synthetic line\n", count: 80)
    var following = true
    var jump = 0
}
private struct ScrollProbeView: View {
    let probe: ScrollProbe
    var body: some View {
        @Bindable var probe = probe
        ResultFollowingScrollView(resetID: nil, jump: probe.jump, following: $probe.following) {
            Text(probe.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor @Test func streamScrollFollowsBottomButPreservesReadingPosition() async throws {
    _ = NSApplication.shared
    let probe = ScrollProbe()
    let hosting = NSHostingView(rootView: ScrollProbeView(probe: probe).frame(width: 380, height: 240))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 380, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = hosting
    defer { window.close() }
    func settle() async {
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(80))
        hosting.layoutSubtreeIfNeeded()
    }
    await settle()
    func findScroll(_ view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.compactMap(findScroll).first
    }
    let scroll = try #require(findScroll(hosting))
    let document = try #require(scroll.documentView)
    #expect(document.frame.height > 800)
    #expect(abs(scroll.documentVisibleRect.maxY - document.frame.height) < 34)
    scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
    await settle()
    #expect(!probe.following)
    let position = scroll.contentView.bounds.origin
    probe.text += String(repeating: "More synthetic text\n", count: 20)
    await settle()
    #expect(scroll.contentView.bounds.origin == position)
    probe.jump += 1
    await settle()
    #expect(abs(scroll.documentVisibleRect.maxY - document.frame.height) < 34)
}

@Test func resultKeyboardLeavesCompositionAndNativeCopyUntouched() {
    #expect(ResultWindowKeyAction.resolve(code: 36, text: "\r", modifiers: .command, editingQuestion: true, markedText: true) == .passThrough)
    #expect(ResultWindowKeyAction.resolve(code: 53, text: nil, modifiers: [], editingQuestion: true, markedText: true) == .passThrough)
    #expect(ResultWindowKeyAction.resolve(code: 36, text: "\r", modifiers: [], editingQuestion: true, markedText: false) == .passThrough)
    #expect(ResultWindowKeyAction.resolve(code: 36, text: "\r", modifiers: .command, editingQuestion: true, markedText: false) == .send)
    #expect(ResultWindowKeyAction.resolve(code: 36, text: "\r", modifiers: .command, editingQuestion: false, markedText: false) == .copyAndReturn)
    #expect(ResultWindowKeyAction.resolve(code: 8, text: "c", modifiers: .command, editingQuestion: false, markedText: false) == .passThrough)
}

@MainActor @Test func resultMarkdownRendersLongAnswersAndCodeInBothThemes() throws {
    _ = NSApplication.shared
    let text = """
    # 合成内容 · 请求取消

    保留 **完整回答**，上移阅读时暂停跟随。

    - 请求彼此独立
    - `Esc` 停止当前任务

    ```swift
    let task = Task {
        try await service.run()
    }
    task.cancel()
    ```

    代码可独立复制，原始 Markdown 也可整体复制。
    """
    for dark in [false, true] {
        let view = ResultAnswerView(text: text, markdown: true, copyCode: { _ in })
            .padding(20).frame(width: 420, height: 520, alignment: .topLeading)
            .foregroundStyle(Tokens.palette(dark ? .dark : .light).foreground)
            .background(Tokens.palette(dark ? .dark : .light).background)
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.close()
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        if let directory = ProcessInfo.processInfo.environment["ROARKT_RESULT_RENDER_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("markdown-\(dark ? "dark" : "light").png"))
        }
    }
}

@Test @MainActor func newResultAvoidsCoveringOrHidingBehindPinnedResult() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let pinned = CGRect(x: 400, y: 200, width: 420, height: 550)
    let next = ResultWindowGeometry.avoiding(pinned, occupied: [pinned], screen: screen)
    #expect(screen.contains(next) && !next.intersects(pinned))
    #expect(ResultWindowGeometry.avoiding(pinned, occupied: [], screen: screen) == pinned)
}
