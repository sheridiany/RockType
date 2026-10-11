import AVFoundation
import Foundation

@MainActor protocol VoiceRecording: AnyObject {
    var level: Double { get }
    var isRecording: Bool { get }
    func start() throws
    func finish() -> Data
    func cancel()
}

private final class VoiceSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var samples = Data()
    private var accepting = true
    private var peak: Float = 0
    private var meter: Double = 0
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let values = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        guard accepting else { return }
        let count = min(Int(buffer.frameLength), (60 * 16_000 * 4 - samples.count) / 4)
        guard count > 0 else { return }
        var energy: Float = 0
        for index in 0..<count { energy += values[index] * values[index] }
        let rms = sqrt(energy / Float(count))
        peak = max(peak, rms)
        meter = min(1, Double(rms) * 12)
        samples.append(UnsafeBufferPointer(start: values, count: count))
    }
    var level: Double { lock.lock(); defer { lock.unlock() }; return meter }
    func take() -> Data {
        lock.lock(); defer { lock.unlock() }
        accepting = false
        defer { samples = Data(); meter = 0 }
        return peak >= 0.001 ? samples : Data()
    }
}

/// AVAudioConverter consumes this input synchronously during convert(). The buffer is
/// retained and read-only for that call; the one-shot flag is protected for its Sendable callback.
private final class VoiceConversionInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var supplied = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func provide(_ state: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock(); defer { lock.unlock() }
        if supplied { state.pointee = .noDataNow; return nil }
        supplied = true; state.pointee = .haveData
        return buffer
    }
}

@MainActor final class VoiceAudioCapture: VoiceRecording {
    private var engine: AVAudioEngine?
    private var samples: VoiceSamples?
    var level: Double { samples?.level ?? 0 }
    var isRecording: Bool { engine?.isRunning == true }
    func start() throws {
        cancel()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: output) else { throw VoiceFailure.unavailable }
        let samples = VoiceSamples()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / format.sampleRate)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
            let source = VoiceConversionInput(buffer)
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, state in
                source.provide(state)
            }
            if error == nil, status != .error { samples.append(converted) }
        }
        self.engine = engine; self.samples = samples
        do { try engine.start() } catch { cancel(); throw error }
    }
    func finish() -> Data {
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        let data = samples?.take() ?? Data()
        samples = nil
        return data
    }
    func cancel() { _ = finish() }
}
