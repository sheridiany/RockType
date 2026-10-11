import AVFoundation
import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

/// Regression for the Swift 6 isolation trap: AVAudioEngine delivers taps on its realtime
/// thread, so the processing path must run off the main actor without crashing.
@Test func voiceTapProcessesBuffersOnABackgroundThread() async throws {
    let input = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
    let (processor, take) = try #require(VoiceTapProcessor.forTesting(input: input))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4800))
    buffer.frameLength = 4800
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<4800 { channel[index] = sin(Float(index) * 0.05) * 0.3 }
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        DispatchQueue.global(qos: .userInteractive).async {
            processor.process(buffer)
            done.resume()
        }
    }
    #expect(take().count > 0)
}

@Test func voiceCaptureIsBoundedAndPreviewSnapshotsDoNotConsumeFinalAudio() throws {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 30 * 16_000))
    buffer.frameLength = buffer.frameCapacity
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(buffer.frameLength) { channel[index] = 0.2 }
    let samples = VoiceSamples()
    #expect(samples.preview(after: 0) == nil)
    for _ in 0..<7 { samples.append(buffer) }
    #expect(samples.sampleCount == 180 * 16_000)
    let first = try #require(samples.preview(after: 0))
    #expect(first.count == 3 * 64_000)
    #expect(samples.preview(after: -1) == nil)
    #expect(samples.preview(after: 180 * 16_000) == nil)
    let final = samples.take()
    #expect(final.count == 180 * 64_000)
    #expect(final.prefix(first.count) == first)
    #expect(samples.preview(after: 0) == nil)
    samples.append(buffer)
    #expect(samples.take().isEmpty, "A stopped recorder cannot accept late tap buffers")
}

/// Synthetic stage microbenchmark: real resampler and buffer sealing, no microphone/IMK.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ROARKT_VOICE_PERFORMANCE"] == "1"))
func syntheticVoiceCaptureAndCleanupCosts() throws {
    let input = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
    let (processor, take) = try #require(VoiceTapProcessor.forTesting(input: input))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 2048))
    buffer.frameLength = 2048
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<2048 { channel[index] = sin(Float(index) * 0.05) * 0.3 }
    let start = ProcessInfo.processInfo.systemUptime
    for _ in 0..<141 { processor.process(buffer) } // about six seconds at 48 kHz
    let converted = ProcessInfo.processInfo.systemUptime
    let audio = take()
    let stopped = ProcessInfo.processInfo.systemUptime
    let cleaned = RoarkTCore.VoiceTextCleaner.clean("嗯，今天我们一起检查项目进度。请保留标点，完成测试以后再提交代码。")
    let normalized = ProcessInfo.processInfo.systemUptime
    #expect(!audio.isEmpty && !cleaned.isEmpty)
    let output: [String: Double] = ["audioSeconds": Double(audio.count) / 64_000,
        "resampleDuringCapture": converted - start, "sealBufferAfterRelease": stopped - converted,
        "cleanup": normalized - stopped]
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    try FileManager.default.createDirectory(at: root.appendingPathComponent(".build/r5-ime"), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        .write(to: root.appendingPathComponent(".build/r5-ime/capture-costs.json"))
    print("Synthetic capture stage costs: \(output)")
}
