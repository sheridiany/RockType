import AppKit
import SwiftUI
import Testing
@testable import RoarkTApp

@MainActor private final class RecordingSpeechDriver: SpeechDriving {
    var voices: [SystemSpeechVoice] = [
        .init(identifier: "synthetic-en", language: "en-US"), .init(identifier: "synthetic-zh", language: "zh-CN")]
    let defaultLanguage = "en-US"
    struct Call {
        var text: String
        var voice: SystemSpeechVoice
        var request: UUID
        var report: @MainActor @Sendable (UUID, SpeechPlaybackEvent) -> Void
    }
    var calls: [Call] = []
    var stops = 0
    var accepts = true
    func speak(_ text: String, voice: SystemSpeechVoice, request: UUID,
               report: @escaping @MainActor @Sendable (UUID, SpeechPlaybackEvent) -> Void) -> Bool {
        calls.append(.init(text: text, voice: voice, request: request, report: report)); return accepts
    }
    func stop() { stops += 1 }
    func send(_ event: SpeechPlaybackEvent, call index: Int) { calls[index].report(calls[index].request, event) }
}

@Suite(.serialized) @MainActor struct TextSpeakerTests {
    @Test func replacementStopAndOldCallbacksNeverRevivePlayback() {
        let driver = RecordingSpeechDriver()
        let subject = TextSpeaker(driver: driver, allowed: { true })
        defer { subject.stop() }
        subject.speak("Synthetic first", language: "en")
        #expect(subject.state == .preparing)
        driver.send(.started, call: 0)
        #expect(subject.isSpeaking)
        subject.speak("第二段合成文字", language: "zh-Hans")
        #expect(driver.calls.count == 2 && driver.calls[1].voice.identifier == "synthetic-zh")
        driver.send(.cancelled, call: 0); driver.send(.finished, call: 0)
        #expect(subject.state == .preparing)
        driver.send(.started, call: 1)
        #expect(subject.isSpeaking)
        subject.stop()
        driver.send(.started, call: 1); driver.send(.finished, call: 1)
        #expect(subject.state == .idle)
    }

    @Test func onlyOneSpeakerCanPlayAndUnrelatedStopDoesNotInterruptIt() {
        let firstDriver = RecordingSpeechDriver(), secondDriver = RecordingSpeechDriver()
        let first = TextSpeaker(driver: firstDriver, allowed: { true })
        let second = TextSpeaker(driver: secondDriver, allowed: { true })
        defer { first.stop(); second.stop() }
        first.speak("First synthetic", language: "en-US"); firstDriver.send(.started, call: 0)
        let stopped = firstDriver.stops
        second.speak("Second synthetic", language: "en-US")
        #expect(first.state == .idle && firstDriver.stops > stopped)
        secondDriver.send(.started, call: 0)
        let secondStops = secondDriver.stops
        first.stop(); firstDriver.send(.finished, call: 0)
        #expect(second.isSpeaking && secondDriver.stops == secondStops)
        secondDriver.send(.finished, call: 0)
        #expect(second.state == .idle)
    }

    @Test func protectionEmptyOversizedAndMissingVoiceDoNotSpeak() {
        let driver = RecordingSpeechDriver()
        var readable = false
        let speaker = TextSpeaker(driver: driver, allowed: { readable })
        defer { speaker.stop() }
        speaker.speak("Synthetic", language: "en")
        #expect(speaker.state == .failed(.protectedInput) && driver.calls.isEmpty)
        readable = true
        speaker.speak(" \n "); #expect(speaker.state == .idle && driver.calls.isEmpty)
        speaker.speak(String(repeating: "字", count: 32_001))
        #expect(speaker.state == .failed(.tooLong) && driver.calls.isEmpty)
        speaker.speak("Synthetic", language: "fr-FR")
        #expect(speaker.state == .failed(.unavailableVoice) && driver.calls.isEmpty)
        speaker.speak("Synthetic", language: "en")
        readable = false; speaker.checkPlayback()
        #expect(speaker.state == .failed(.protectedInput))
        driver.send(.started, call: 0)
        #expect(!speaker.isActive)
    }

    @Test func startupFailureAndTimeoutAreRecoverable() {
        let driver = RecordingSpeechDriver()
        var now = 1.0
        let speaker = TextSpeaker(driver: driver, allowed: { true }, now: { now })
        defer { speaker.stop() }
        driver.accepts = false
        speaker.speak("Synthetic", language: "en")
        #expect(speaker.state == .failed(.unavailableEngine))
        driver.accepts = true
        speaker.speak("Synthetic", language: "en")
        now = 12; speaker.checkPlayback()
        #expect(speaker.state == .failed(.unavailableEngine))
        driver.send(.started, call: 1)
        #expect(!speaker.isActive)
        speaker.speak("Synthetic", language: "en")
        driver.send(.started, call: 2)
        now = 100; speaker.checkPlayback()
        #expect(speaker.isSpeaking) // A long, already-started utterance is not subject to the startup deadline.
    }

    @Test func systemLanguageDetectionAndRegionalVoiceSelection() {
        let voices: [SystemSpeechVoice] = [
            .init(identifier: "us", language: "en-US", quality: 1), .init(identifier: "gb", language: "en-GB", quality: 2),
            .init(identifier: "cn", language: "zh-CN"), .init(identifier: "tw", language: "zh-TW")]
        #expect(TextSpeaker.voice(for: "en_US", in: voices)?.identifier == "us")
        #expect(TextSpeaker.voice(for: "en", in: voices)?.identifier == "gb")
        #expect(TextSpeaker.voice(for: "zh-Hans", in: voices)?.identifier == "cn")
        #expect(TextSpeaker.voice(for: "zh-Hant", in: voices)?.identifier == "tw")
        #expect(TextSpeaker.voice(for: "fr", in: voices) == nil)
        #expect(TextSpeaker.language(for: "This is a synthetic sentence for a local speech test.", hint: nil, fallback: "zh-CN") == "en")
        #expect(TextSpeaker.language(for: "这是本机朗读测试的合成文字。", hint: nil, fallback: "en-US").hasPrefix("zh"))
        #expect(TextSpeaker.language(for: "Synthetic", hint: "fr-FR", fallback: "en-US") == "fr-FR")
    }

    @Test func owningWindowCloseOrDetachmentStopsWithoutClosingOtherWindows() {
        _ = NSApplication.shared
        let driver = RecordingSpeechDriver()
        let subject = TextSpeaker(driver: driver, allowed: { true })
        let owner = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 60), styleMask: .borderless, backing: .buffered, defer: false)
        let other = NSPanel(contentRect: owner.frame, styleMask: .borderless, backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false; other.isReleasedWhenClosed = false
        let anchor = SpeechWindowAnchor(speaker: subject)
        owner.contentView = anchor
        defer { anchor.detach(); owner.contentView = nil; owner.close(); other.close() }
        subject.speak("Synthetic", language: "en")
        other.close()
        #expect(subject.isActive)
        owner.close() // The host is deliberately retained: onDisappear alone is insufficient.
        #expect(!subject.isActive && driver.stops >= 2)
        driver.send(.started, call: 0); #expect(!subject.isActive)
        subject.speak("Synthetic", language: "en")
        anchor.detach()
        #expect(!subject.isActive)
    }

    @Test func ownerReleaseStopsDriver() async {
        let driver = RecordingSpeechDriver()
        var speaker: TextSpeaker? = TextSpeaker(driver: driver, allowed: { true })
        weak var released = speaker
        speaker?.speak("Synthetic", language: "en")
        let stops = driver.stops
        speaker = nil
        for _ in 0..<30 { if driver.stops > stops { break }; await Task.yield() }
        #expect(released == nil && driver.stops > stops)
    }

    @Test func renderButtonStatesInLightDarkAndReducedMotion() throws {
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/t4")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            // Rendering teardown triggers onDisappear, just like a dismissed host. Each theme needs fresh state.
            let idle = TextSpeaker(driver: RecordingSpeechDriver(), allowed: { true })
            let empty = TextSpeaker(driver: RecordingSpeechDriver(), allowed: { true })
            let driver = RecordingSpeechDriver()
            let playing = TextSpeaker(driver: driver, allowed: { true })
            let failure = TextSpeaker(driver: RecordingSpeechDriver(), allowed: { false })
            playing.speak("Synthetic playback", language: "en"); driver.send(.started, call: 0)
            failure.speak("Synthetic blocked", language: "en")
            defer { idle.stop(); empty.stop(); playing.stop(); failure.stop() }
            let p = Tokens.Palette(dark: dark)
            let view = VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                Text("系统朗读").font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                HStack(spacing: Tokens.Space.lg) {
                    cell("就绪", speaker: idle, text: "Synthetic")
                    cell("朗读中", speaker: playing, text: "Synthetic playback")
                    cell("无文字", speaker: empty, text: "")
                    cell("暂不可用", speaker: failure, text: "Synthetic blocked")
                }
            }.padding(Tokens.Space.lg).foregroundStyle(p.foreground)
                .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.window))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.window).stroke(p.line, lineWidth: Tokens.Size.hairline))
                .padding(Tokens.Space.lg).frame(width: 420).background(p.canvas)
                .environment(\.colorScheme, dark ? .dark : .light).environment(\.designReduceMotion, true)
            let renderer = ImageRenderer(content: view.fixedSize()); renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(playing.isSpeaking && failure.notice != nil)
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("speak-button-\(dark ? "dark" : "light").png"))
            #expect(image.width == 840 && image.height > 150)
        }
    }

    private func cell(_ label: String, speaker: TextSpeaker, text: String) -> some View {
        VStack(spacing: Tokens.Space.sm) {
            SpeakButton(speaker: speaker, text: text, language: "en")
            Text(label).font(Tokens.Typography.font(Tokens.Typography.caption))
        }.frame(minWidth: 64)
    }
}
