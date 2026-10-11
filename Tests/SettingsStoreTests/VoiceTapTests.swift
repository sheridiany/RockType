import AVFoundation
import Foundation
import Testing
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
