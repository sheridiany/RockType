import Foundation
import Testing
@testable import RoarkTCore

@Test func voiceSegmentsPreferSilenceWithoutLosingOrDuplicatingSamples() {
    let rate = VoiceAudioSegmentation.sampleRate
    var samples = [Float](repeating: 0.1, count: 75 * rate + 13)
    for seconds in [25, 50] {
        samples.replaceSubrange((seconds * rate)..<((seconds + 1) * rate), with: repeatElement(Float(0), count: rate))
    }
    let ranges = VoiceAudioSegmentation.ranges(in: samples)
    #expect(ranges.count == 3)
    #expect(ranges[0].upperBound >= 25 * rate && ranges[0].upperBound <= 26 * rate)
    #expect(ranges[1].upperBound >= 50 * rate && ranges[1].upperBound <= 51 * rate)
    #expect(ranges.first?.lowerBound == 0 && ranges.last?.upperBound == samples.count)
    for pair in zip(ranges, ranges.dropFirst()) { #expect(pair.0.upperBound == pair.1.lowerBound) }
    #expect(ranges.allSatisfy { $0.count > 0 && $0.count <= 28 * rate })
    #expect(ranges.flatMap { Array(samples[$0]) } == samples)
}

@Test func voiceSegmentsEnforceHardLimitEvenWithoutSilence() {
    let rate = VoiceAudioSegmentation.sampleRate
    for count in [0, 1, rate - 1, 28 * rate, 28 * rate + 1, 180 * rate] {
        let samples = [Float](repeating: 0.2, count: count)
        let ranges = VoiceAudioSegmentation.ranges(in: samples)
        #expect(ranges.reduce(0) { $0 + $1.count } == count)
        #expect(ranges.allSatisfy { $0.count > 0 && $0.count <= 28 * rate })
        for pair in zip(ranges, ranges.dropFirst()) { #expect(pair.0.upperBound == pair.1.lowerBound) }
    }
}

@Test func voiceJoiningPreservesPunctuationAndLegitimateRepetition() {
    #expect(VoiceAudioSegmentation.join(["你好，", "世界。", "世界。", "", "下一段！"]) == "你好，世界。世界。下一段！")
    #expect(VoiceAudioSegmentation.join(["Hello,", "world.", "Again!"]) == "Hello, world. Again!")
    #expect(VoiceAudioSegmentation.join(["使用 SwiftUI", "开发界面。", "𠀀。"]) == "使用 SwiftUI开发界面。𠀀。")
}

@Test func longVoiceTicketStillRejectsContextChangesReuseAndExpiry() {
    let context = VoiceCommitTicket.Context(activation: UUID(), applicationPID: 10, selection: NSRange(location: 0, length: 0))
    let changed = VoiceCommitTicket.Context(activation: UUID(), applicationPID: 10, selection: context.selection)
    var ticket = VoiceCommitTicket()
    let long = ticket.capture(context, now: 0, lifetime: VoiceCommitTicket.dictationLifetime)
    let accepted = ticket.consume(long, context: context, now: 250, deadline: 590)
    #expect(accepted)
    let reused = ticket.consume(long, context: context, now: 251, deadline: 590)
    #expect(!reused)
    let moved = ticket.capture(context, now: 0, lifetime: VoiceCommitTicket.dictationLifetime)
    let rejected = ticket.consume(moved, context: changed, now: 200, deadline: 590)
    #expect(!rejected)
    let expired = ticket.capture(context, now: 0, lifetime: .greatestFiniteMagnitude)
    let timedOut = ticket.consume(expired, context: context, now: 601, deadline: 700)
    #expect(!timedOut)
}
