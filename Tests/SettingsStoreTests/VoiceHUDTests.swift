import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import RoarkTApp

@MainActor @Test func voiceCapsuleHasNoNormalTextAndOnlyUncommittedResultsExpand() {
    let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { true })
    for state in [RoarkTVoiceHUD.State.preparing, .recording, .processing, .polishing, .success("已填入"), .noSpeech] {
        hud.render(state)
        #expect(hud.presentationSize.width <= 120 && hud.presentationSize.height == 32)
        #expect(!hud.acceptsKeyboardFocus)
        #expect(hud.content.heading.isHidden && hud.content.heading.stringValue.isEmpty)
        #expect(hud.content.detailText.stringValue.isEmpty && hud.content.copyButton.isHidden)
        #expect(!hud.content.waveform.isHidden)
        #expect(hud.content.close.alphaValue == 0)
    }
    for state in [RoarkTVoiceHUD.State.result(String(repeating: "合成结果。", count: 300))] {
        hud.render(state)
        #expect(hud.presentationSize == NSSize(width: 280, height: 164))
        #expect(!hud.content.heading.isHidden && !hud.content.copyButton.isHidden)
        #expect(hud.content.detailText.stringValue == state.detail)
    }
    hud.hide()
    #expect(hud.content.detailText.stringValue.isEmpty)
    #expect(hud.state.detail == nil && !hud.content.isAnimating)
}

@MainActor @Test func voiceHUDAdapterCopiesOnlyExplicitFailureAndHonorsProtection() {
    let state = VoiceHUDState()
    let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { true })
    var allowed = true; var copied = [String]()
    let adapter = VoiceHUDController(state: state, hud: hud, canCopy: { allowed }, copy: { copied.append($0) })
    for (phase, expected) in [(VoiceHUDState.Phase.preparing, RoarkTVoiceHUD.State.preparing), (.loading, .preparing),
                             (.recording, .recording), (.recognizing, .processing), (.polishing, .polishing), (.noSpeech, .noSpeech)] {
        state.phase = phase; adapter.show()
        #expect(hud.state == expected)
        hud.onCopy?()
        #expect(copied.isEmpty)
    }
    state.phase = .failed; state.result = "合成的未填入结果"; state.message = "输入位置变化"
    adapter.show(); hud.content.copyButton.performClick(nil)
    #expect(copied == [state.result])
    allowed = false; hud.content.copyButton.performClick(nil)
    #expect(copied.count == 1)
    allowed = true; state.result = ""; adapter.show(); hud.content.copyButton.performClick(nil)
    #expect(copied.count == 1, "A notice must not copy error text")
    adapter.hide()
}

@MainActor @Test func voiceWaveformUsesRealSamplesAndReductionStopsAmbientWork() {
    var reduced = false
    let content = RoarkTVoiceHUDContent(reduceMotion: { reduced })
    content.render(.recording); content.setRunning(true)
    #expect(content.isAnimating)
    #expect(content.waveform.levels.allSatisfy { $0 == 0 })
    content.waveform.append(decibels: -10)
    #expect(content.waveform.levels.last == 1)
    for _ in 0..<9 { content.waveform.append(decibels: -.infinity) }
    #expect(content.waveform.levels.allSatisfy { $0 == 0 })
    reduced = true; content.refreshMotion()
    #expect(!content.isAnimating && content.waveform.reducedMotion)
    content.waveform.append(decibels: -20)
    #expect(content.waveform.levels.last! > 0, "Reduced motion still displays actual amplitude")
    reduced = false; content.refreshMotion()
    #expect(content.isAnimating)
    content.setRunning(false)
    #expect(!content.isAnimating)
}

@MainActor @Test func voiceDismissalCannotHideAReplacementAndContentClearsBeforeFade() async throws {
    for reduced in [false, true] {
        let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { reduced })
        hud.show(.preparing)
        hud.show(.recording)
        #expect((hud.content.layer?.animation(forKey: "entrance") == nil) == reduced,
                "A warm model must not cancel the entrance spring at the preparation-to-recording handoff")
        hud.show(.success("已填入"), dismissAfter: 0.05)
        hud.show(.recording)
        try await Task.sleep(for: .milliseconds(100))
        #expect(hud.isPresented && hud.state == .recording)
        hud.show(.result("不得保留的合成内容")); hud.hide()
        #expect(hud.content.detailText.stringValue.isEmpty)
        hud.show(.recording)
        try await Task.sleep(for: .milliseconds(300))
        #expect(hud.isPresented && hud.state == .recording)
        #expect(hud.content.layer?.animation(forKey: "exitOpacity") == nil)
        hud.show(.success("已填入")); hud.hide()
        if !reduced { #expect(hud.content.waveform.mode == .success, "Keep the checkmark through exit, without a preparation flash") }
        hud.show(.recording)
        #expect(hud.content.waveform.levels.allSatisfy { $0 == 0 }, "A new hold must not reuse the previous meter history")
        hud.hide()
    }
}

@MainActor @Test func voiceCompletionAndNoSpeechDisappearAutomatically() async throws {
    let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { true })
    for state in [RoarkTVoiceHUD.State.success("已填入"), .noSpeech] {
        hud.show(state)
        try await Task.sleep(for: .milliseconds(800))
        #expect(!hud.isPresented && !hud.content.isAnimating)
    }
}

@MainActor @Test func voiceB3RendersEveryStateAndMotionFrames() throws {
    _ = NSApplication.shared
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent(".build/b3")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let states: [(String, RoarkTVoiceHUD.State)] = [
        ("preparing", .preparing), ("recording", .recording), ("silent", .recording),
        ("recognizing", .processing), ("polishing", .polishing), ("success", .success("已填入")),
        ("no-speech", .noSpeech), ("error", .notice(title: "语音模型未下载", detail: "请在设置 → 语音下载模型，再按住 Fn 重试。")),
        ("uncommitted", .result("这是一段用于离屏验收的合成文字，包含标点和完整结果。", reason: "输入位置已变化，请复制结果。"))]
    for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        for (name, state) in states {
            let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { true })
            hud.content.appearance = NSAppearance(named: appearance)
            hud.render(state)
            if name == "recording" {
                for level: Float in [-50, -40, -25, -14, -30, -20, -36, -45, -52] { hud.updateRecording(decibels: level) }
            }
            try saveVoiceView(hud.content, to: output.appendingPathComponent("\(name)-\(theme).png"))
        }
    }
    // Deterministic samples of the exact draw path driven by the live timer.
    for state in [RoarkTVoiceHUD.State.preparing, .processing] {
        let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { false })
        hud.render(state)
        for (index, phase) in [0.1, 0.35, 0.6, 0.85].enumerated() {
            hud.content.waveform.phase = phase
            try saveVoiceView(hud.content, to: output.appendingPathComponent("motion-\(state == .preparing ? "prepare" : "process")-\(index).png"))
        }
    }
    #if DEBUG
    #expect(VoicePresentation.State.allCases.count == 10)
    for state in VoicePresentation.State.allCases {
        let model = VoicePresentation.fixture(state)
        let content = RoarkTVoiceHUDContent(reduceMotion: { true })
        content.setFrameSize(state.presentation.size); content.render(state.presentation)
        for level in model.levels { content.waveform.append(decibels: Float(level * 45 - 55)) }
        try saveVoiceView(content, to: output.appendingPathComponent("gallery-\(state.rawValue).png"))
    }
    #endif
}

@MainActor private func saveVoiceView(_ view: NSView, to url: URL) throws {
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
}

@MainActor @Test func voiceReducedMotionFreezesAmbientFramesButNotLiveMeter() throws {
    func pixels(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
    for reduced in [true, false] {
        let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { reduced })
        for state in [RoarkTVoiceHUD.State.preparing, .processing, .recording] {
            hud.render(state)
            hud.content.waveform.phase = 0.1; let first = try pixels(hud.content)
            hud.content.waveform.phase = 0.65; let second = try pixels(hud.content)
            #expect((first == second) == reduced, "Ambient movement must follow the accessibility setting")
        }
        let silent = try pixels(hud.content)
        hud.updateRecording(decibels: -10)
        #expect(try pixels(hud.content) != silent, "Actual input remains visible with reduced motion")
        hud.show(.recording)
        #expect((hud.content.layer?.animation(forKey: "entrance") == nil) == reduced)
        hud.hide(); hud.show(.recording)
        #expect(hud.content.layer?.animation(forKey: "exitOpacity") == nil)
        hud.hide()
    }
}

#if DEBUG
@MainActor @Test func voiceGalleryExportsTheProductionSurfaceThroughImageRenderer() throws {
    _ = NSApplication.shared
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent(".build/b3")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let entries = InputVoiceGallery.entries.filter { $0.surface == "voice-hud" }
    #expect(entries.count == 10)
    for entry in entries {
        for theme in GalleryTheme.allCases {
            let renderer = ImageRenderer(content: GalleryPreview(entry: entry, theme: theme, reduceMotion: true).fixedSize())
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            #expect(bitmap.pixelsWide <= 560 && bitmap.pixelsHigh <= 328)
            let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            #expect(center.alphaComponent > 0.9, "Gallery must render the surface, not an unsupported-view placeholder")
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("gallery-export-\(entry.state)-\(theme.rawValue).png"))
        }
    }
}
#endif

@MainActor @Test func voiceB3NoticesAreCompactAndNeverOfferCopy() {
    let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { true })
    for message in ["请重试。", "请在设置 → 权限中允许麦克风，再按住 Fn。", String(repeating: "合成的长提示", count: 30)] {
        hud.render(.notice(title: "语音未完成", detail: message))
        #expect(hud.presentationSize.width <= 280 && hud.presentationSize.height <= 56)
        #expect(hud.content.copyButton.isHidden)
        #expect(hud.content.heading.maximumNumberOfLines == 2)
    }
    hud.render(.result(" \n ", reason: "输入位置无法确认"))
    #expect(hud.content.copyButton.isHidden && hud.presentationSize.height <= 56)
    hud.hide()
}

@MainActor @Test func voiceB3NoticeHidesAutomaticallyWithoutDismissingAResult() async throws {
    let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { true })
    hud.show(.notice(title: "语音未完成", detail: "请先下载模型。"))
    try await Task.sleep(for: .milliseconds(3800))
    #expect(!hud.isPresented && hud.content.heading.stringValue.isEmpty)
    hud.show(.notice(title: "语音未完成", detail: "请重试。"), dismissAfter: 0.02)
    hud.show(.result("需要保留的合成结果。"))
    try await Task.sleep(for: .milliseconds(100))
    #expect(hud.isPresented && !hud.content.copyButton.isHidden)
    #expect(hud.content.detailText.stringValue.contains("需要保留的合成结果。"))
    hud.hide()
}
