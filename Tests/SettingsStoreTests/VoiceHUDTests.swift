import AppKit
import Testing
@testable import RoarkTApp

@Test @MainActor func voiceHUDUsesCompactNonactivatingLayout() {
    _ = NSApplication.shared
    let hud = RoarkTVoiceHUD()
    for state in [RoarkTVoiceHUD.State.recording, .preparing, .processing, .success("已填入 · 未发送")] {
        hud.render(state)
        #expect(hud.presentationSize == NSSize(width: 188, height: 36))
        #expect(!hud.acceptsKeyboardFocus)
    }
}

@Test @MainActor func voiceHUDOnlyExpandsDetailsOnRequest() {
    _ = NSApplication.shared
    let hud = RoarkTVoiceHUD()
    let text = String(repeating: "完整识别文字。", count: 500)
    hud.render(.result(text, reason: "输入目标已变化"))
    #expect(hud.presentationSize == NSSize(width: 240, height: 36))
    #expect(hud.state.title == "未能填入")
    #expect(hud.state.detail == "输入目标已变化\n\n" + text)
    hud.toggleDetails()
    #expect(hud.expanded)
    #expect(hud.presentationSize == NSSize(width: 288, height: 180))
    hud.render(.recording)
    #expect(!hud.expanded)
    #expect(hud.state.detail == nil)
    hud.toggleDetails()
    #expect(!hud.expanded)
}

@Test @MainActor func voiceHUDMeterRequiresRealSamples() {
    let waveform = RoarkTVoiceHUDWaveform()
    #expect(waveform.levels.allSatisfy { $0 == 0 })
    waveform.append(decibels: -10)
    #expect(waveform.levels.last == 1)
    for _ in 0..<9 { waveform.append(decibels: -80) }
    #expect(waveform.levels.allSatisfy { $0 == 0 })
    waveform.append(decibels: .nan)
    #expect(waveform.levels.last == 0)
    waveform.reset()
    #expect(waveform.levels.count == 9)
}

@Test @MainActor func voiceHUDLifecycleAdapterAndEvidence() throws {
    _ = NSApplication.shared
    let state = VoiceHUDState()
    let hud = RoarkTVoiceHUD(present: { _ in })
    let controller = VoiceHUDController(state: state, hud: hud)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent(".build/ime-evidence")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let panel = try #require(Mirror(reflecting: hud).children.first { $0.label == "panel" }?.value as? NSPanel)
    let view = try #require(panel.contentView)
    func render(_ name: String) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
    }
    for (phase, name) in [(VoiceHUDState.Phase.preparing, "preparing"), (.recording, "recording"), (.recognizing, "processing"), (.done, "done")] {
        state.phase = phase
        state.message = "已填入 · 未发送"
        controller.show()
        if phase == .recording {
            state.seconds = 8
            for level in [0.2, 0.6, 0.9, 0.3, 0.8, 0.4, 0.2, 0.7, 0.3] {
                state.levels.removeFirst(); state.levels.append(level)
            }
        }
        #expect(hud.presentationSize == NSSize(width: 188, height: 36))
        try render("voice-" + name)
    }
    state.phase = .failed
    state.message = "输入位置已变化或提交超时，请复制结果。"
    state.result = "这是一段用于离屏验收的示例文字。"
    controller.show()
    #expect(hud.state == .result(state.result, reason: state.message))
    try render("voice-result")
    hud.toggleDetails()
    #expect(hud.presentationSize == NSSize(width: 288, height: 180))
    try render("voice-result-expanded")
    state.result = ""
    state.message = "请先在设置 → 语音下载模型。"
    controller.show()
    #expect(hud.state == .notice(title: "语音输入", detail: state.message))
    try render("voice-notice")
    controller.hide()
    #expect(!panel.isVisible)
}
