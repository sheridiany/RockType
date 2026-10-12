import AppKit
import SwiftUI
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class T5RenderRunner: OperationRunner {
    var continuation: AsyncStream<OperationEvent>.Continuation?
    func start() {}
    func stop() { continuation?.finish() }
    func cancel() { continuation?.finish() }
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        AsyncStream { continuation = $0 }
    }
}

@MainActor @Test func t5GenericResultsRenderNarrowBusyAndFailed() async throws {
    guard let path = ProcessInfo.processInfo.environment["ROARKT_T5_RENDER_DIR"] else { return }
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for templateID in ["summarize", "polish", "explain"] {
        for phase in (templateID == "summarize" ? ["done", "streaming", "failed"] : ["done"]) {
            for dark in [false, true] {
                let runner = T5RenderRunner()
                let controller = ResultWindowController(runner: runner, settings: { .defaults }, feedback: { _ in }, readable: { true })
                defer { controller.stop() }
                var template = try #require(OperationTemplate.defaults.first { $0.id == templateID })
                if templateID == "explain" { template.name = "解释一个很长的自定义操作名称" }
                let snapshot = ContentSnapshot(text: "Synthetic source: keep a concise result and preserve code.\nlet value = 42",
                    source: .init(pid: 42, applicationName: "Synthetic editor"), method: .accessibility)
                let session = OperationSession(snapshot: snapshot, turns: [.init(question: "", answer: "这是用于排版验证的合成结果。\n\n保留段落，并让主要操作保持可见。")])
                if phase == "done" {
                    controller.state.show(OperationResult(session: session, templateID: templateID, text: session.turns[0].answer,
                        engine: "Synthetic model with a deliberately long display name"), template: template, settings: .defaults)
                } else {
                    controller.state.show(OperationRequest(session: .init(snapshot: snapshot), template: template, settings: .defaults))
                    if phase == "streaming" { runner.continuation?.yield(.delta("这是正在逐步生成的合成结果…")) }
                    else { runner.continuation?.yield(.failed(.unavailable)) }
                    for _ in 0..<100 where controller.state.phase == .connecting { try await Task.sleep(for: .milliseconds(5)) }
                    #expect(controller.state.phase == (phase == "streaming" ? .streaming : .failed))
                }
                #expect(!controller.state.asking && !controller.state.sourceExpanded)
                let host = NSHostingView(rootView: LiveResultWindowView(controller: controller)
                    .environment(\.colorScheme, dark ? .dark : .light))
                let size = CGSize(width: 340, height: 360)
                let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.contentView = host
                host.frame = CGRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(
                    "result-\(templateID)-\(phase)-\(dark ? "dark" : "light")-340.png"))
                #expect(host.bounds.width == 340)
                panel.contentView = nil; panel.close()
            }
        }
    }
}
