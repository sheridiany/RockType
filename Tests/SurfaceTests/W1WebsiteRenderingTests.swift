import AppKit
import SwiftUI
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class W1Runner: OperationRunner {
    func start() {}; func stop() {}; func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> { AsyncStream { _ in } }
}
@MainActor @Test func websiteProductRenders() async throws {
    guard let path = ProcessInfo.processInfo.environment["ROARKT_WEBSITE_RENDER_DIR"] else { return }
    _ = NSApplication.shared
    let directory = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    func save(_ view: NSView, _ name: String) throws {
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
    }
    func hosted<V: View>(_ view: V, size: CGSize, dark: Bool, name: String) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        panel.contentView = host; host.frame = CGRect(origin: .zero, size: size)
        try save(host, name); panel.contentView = nil; panel.close()
    }
    for dark in [false, true] {
        let theme = dark ? "dark" : "light"
        var settings = AppSettings.defaults
        settings.general.appearance = dark ? .dark : .light
        let request = OperationRequest(session: .init(snapshot: .init(text: "Make room for what matters.", source: .init(pid: 0, applicationName: "Notes"), method: .accessibility)), template: .defaults[0], settings: settings)
        let previous = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = TranslateWindowController(request: request, runner: W1Runner(), settings: { settings }, allowed: { true }, defaults: nil,
            wordLookup: WordLookup(allowed: { true }, provider: { _ in nil }))
        controller.show(source: nil, anchor: nil, completed: .init(session: request.session, templateID: "translate", text: "把时间留给重要的事。", engine: "Apple Translation"))
        let panel = try #require(NSApp.windows.first { !previous.contains(ObjectIdentifier($0)) })
        panel.orderOut(nil)
        for _ in 0..<8 { panel.contentView?.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(30)) }
        try save(try #require(panel.contentView), "translate-" + theme); controller.close()
        try hosted(LiveSelectionToolbar(actions: SelectionToolbarAction.configured(in: settings), maximumWidth: 420, perform: { _ in }, renderingSnapshot: true), size: CGSize(width: 420, height: 48), dark: dark, name: "selection-" + theme)
        settings.ai.defaultModel = "gpt-4.1"
        settings.translation.model = "gpt-4.1-mini"; settings.selection.assistantModel = "gpt-4.1"
        try hosted(OperationModelSettings(settings: .constant(settings), showAIConnection: {}).padding(16).background(Tokens.palette(dark ? .dark : .light).background), size: CGSize(width: 520, height: 310), dark: dark, name: "models-" + theme)
        let hud = RoarkTVoiceHUDContent(reduceMotion: { true })
        hud.frame = CGRect(origin: .zero, size: RoarkTVoiceHUD.State.recording.size); hud.render(.recording)
        for level: Float in [-40, -30, -17, -34, -11, -20, -31, -22, -40] { hud.waveform.append(decibels: level) }
        try save(hud, "voice-" + theme)
        let image = NSImage(size: CGSize(width: 760, height: 480))
        image.lockFocus()
        NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.23, blue: 0.40, alpha: 1), ending: NSColor(srgbRed: 0.45, green: 0.61, blue: 0.60, alpha: 1))!.draw(in: CGRect(x: 0, y: 0, width: 760, height: 480), angle: -25)
        ("把灵感\n留在这一刻。" as NSString).draw(in: CGRect(x: 95, y: 145, width: 570, height: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 50, weight: .medium), .foregroundColor: NSColor.white])
        image.unlockFocus()
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 760, height: 480), image: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        canvas.allowed = { true }; canvas.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let canvasPanel = NSPanel(contentRect: canvas.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        canvasPanel.isReleasedWhenClosed = false; canvasPanel.contentView = canvas
        canvas.restore(CGRect(x: 60, y: 50, width: 640, height: 300)); canvas.selectTool(.arrow)
        try save(canvas, "screenshot-" + theme); canvasPanel.contentView = nil; canvasPanel.close()
    }
}
