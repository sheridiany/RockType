import AppKit
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class T9LayoutRunner: OperationRunner {
    func start() {}; func stop() {}; func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> { AsyncStream { _ in } }
}

@Suite(.serialized) @MainActor struct T9TranslationLayoutTests {
    @Test func sourceFitsOneLineWrapsAndCapsAtFour() {
        let one = TranslateWindowLayout.sourceHeight("Synthetic", width: 388, expanded: false)
        let four = TranslateWindowLayout.sourceHeight("one\ntwo\nthree\nfour", width: 388, expanded: false)
        let many = String(repeating: "Synthetic\n", count: 20)
        #expect(one < 30)
        #expect(four > one * 2)
        #expect(TranslateWindowLayout.sourceHeight(many, width: 388, expanded: false) == four)
        #expect(TranslateWindowLayout.sourceHeight(many, width: 388, expanded: true) > four)
        #expect(TranslateWindowLayout.sourceHeight("Synthetic\n", width: 388, expanded: false) > one)
        let wrapped = "A synthetic sentence should wrap according to the editor width."
        #expect(TranslateWindowLayout.sourceHeight(wrapped, width: 150, expanded: false)
            > TranslateWindowLayout.sourceHeight(wrapped, width: 388, expanded: false))
    }
    @Test func windowGrowsThenShrinksAndRemainsNonactivating() async throws {
        _ = NSApplication.shared
        let request = OperationRequest(session: .init(snapshot: .init(text: "Keep it clear.", source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)), template: .defaults[0], settings: .defaults)
        let suite = Identifiers.appBundleID + ".t9-layout." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([400.0, 400.0, 420.0, 500.0], forKey: "translateWindowFrame")
        let previous = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = TranslateWindowController(request: request, runner: T9LayoutRunner(), settings: { .defaults }, allowed: { true }, defaults: defaults,
            wordLookup: WordLookup(allowed: { true }, provider: { _ in nil }))
        func result(_ text: String) -> OperationResult {
            .init(session: request.session, templateID: "translate", text: text, engine: "Synthetic")
        }
        controller.show(source: nil, anchor: CGRect(x: 500, y: 600, width: 1, height: 1), completed: result("简短译文。"))
        defer { controller.close() }
        let panel = try #require(NSApp.windows.first { !previous.contains(ObjectIdentifier($0)) })
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        #expect(defaults.object(forKey: "translateWindowHeightLimit") == nil)
        panel.orderOut(nil)
        func settle(_ predicate: () -> Bool) async throws {
            for _ in 0..<80 {
                panel.contentView?.layoutSubtreeIfNeeded()
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(25))
            }
            #expect(predicate())
        }
        try await settle { controller.windowFrame.height > 240 && controller.windowFrame.height < 300 }
        let short = controller.windowFrame.height
        controller.state.showCompleted(result(String(repeating: "长段落用于验证窗口增长和滚动。\n", count: 30)))
        try await settle { controller.windowFrame.height > short + 60 }
        controller.state.showCompleted(result("简短译文。"))
        try await settle { abs(controller.windowFrame.height - short) < 2 }
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
    }
}
