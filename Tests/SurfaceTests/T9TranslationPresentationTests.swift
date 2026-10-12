import AppKit
import SwiftUI
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class T9Runner: OperationRunner {
    func start() {}; func stop() {}; func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> { AsyncStream { _ in } }
}
@MainActor private final class T9Speech: SpeechDriving {
    let voices: [SystemSpeechVoice] = []
    let defaultLanguage = "en-US"
    func speak(_ text: String, voice: SystemSpeechVoice, request: UUID,
               report: @escaping @MainActor @Sendable (UUID, SpeechPlaybackEvent) -> Void) -> Bool { false }
    func stop() {}
}

@Suite(.serialized) @MainActor struct T9TranslationPresentationTests {
    @Test func renderProductionWindowContentSizes() async throws {
        guard let path = ProcessInfo.processInfo.environment["ROARKT_T9_RENDER_DIR"] else { return }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var measurements = ["case\ttheme\twidth\theight"]
        for mode in ["short", "dictionary", "long", "expanded", "empty", "error", "followup", "narrow"] {
            for dark in [false, true] {
                let text = mode == "empty" ? "" : mode == "dictionary" ? "clarity" : ["long", "expanded"].contains(mode)
                    ? (1...12).map { "Synthetic line \($0): preserve the original formatting." }.joined(separator: "\n")
                    : "Keep it clear."
                let request = OperationRequest(session: .init(snapshot: .init(text: text, source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)), template: .defaults[0], settings: .defaults)
                let answer = ["long", "expanded"].contains(mode) ? String(repeating: "保留格式，让表达清楚。\n", count: 24) : mode == "dictionary" ? "清晰；清楚。" : "表达清楚。"
                var settings = AppSettings.defaults
                settings.general.appearance = dark ? .dark : .light
                let suite = Identifiers.appBundleID + ".t9-render." + UUID().uuidString
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                if mode == "narrow" { defaults.set([400.0, 400.0, 360.0, 440.0], forKey: "translateWindowFrame") }
                let previous = Set(NSApp.windows.map(ObjectIdentifier.init))
                let controller = TranslateWindowController(request: request, runner: T9Runner(), settings: { settings }, allowed: { true }, defaults: defaults,
                    wordLookup: WordLookup(allowed: { true }, provider: { _ in mode == "dictionary" ? "clarity /ˈklærəti/ noun 清晰、清楚；表达容易理解。" : nil }),
                    sourceSpeaker: TextSpeaker(driver: T9Speech(), allowed: { true }), translationSpeaker: TextSpeaker(driver: T9Speech(), allowed: { true }))
                controller.show(source: nil, anchor: CGRect(x: 500, y: 600, width: 1, height: 1),
                    completed: .init(session: request.session, templateID: "translate", text: mode == "empty" || mode == "error" ? "" : answer, engine: mode == "narrow" ? "Synthetic model with a long display name" : "Apple Translation"))
                let panel = try #require(NSApp.windows.first { !previous.contains(ObjectIdentifier($0)) })
                panel.orderOut(nil) // Rasterize only our synthetic host; never capture the desktop.
                defer { controller.close() }
                controller.state.expanded = mode == "expanded"
                controller.state.followupExpanded = mode == "followup"
                if mode == "error" { controller.state.result.notice = "连接未完成，请检查网络后重试。" }
                for _ in 0..<8 {
                    panel.contentView?.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(30))
                }
                let host = try #require(panel.contentView)
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("translate-\(mode)-\(dark ? "dark" : "light").png"))
                measurements.append("\(mode)\t\(dark ? "dark" : "light")\t\(host.bounds.width)\t\(host.bounds.height)")
                #expect(!panel.canBecomeKey && !panel.canBecomeMain)
            }
        }
        try measurements.joined(separator: "\n").write(to: directory.appendingPathComponent("sizes.tsv"), atomically: true, encoding: .utf8)
    }
}
