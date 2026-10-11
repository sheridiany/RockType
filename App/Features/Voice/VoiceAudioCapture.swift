import AVFoundation
import Foundation
import RoarkTCore

@MainActor protocol VoiceRecording: AnyObject {
    var level: Double { get }
    var isRecording: Bool { get }
    func start() throws
    func finish() -> Data
    func cancel()
    var sampleCount: Int { get }
    var resamplingSeconds: Double { get }
    func preview(after offset: Int) -> Data?
}

extension VoiceRecording {
    var sampleCount: Int { 0 }
    var resamplingSeconds: Double { 0 }
    func preview(after offset: Int) -> Data? { nil }
}

final class VoiceSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var samples = Data()
    private var accepting = true
    private var peak: Float = 0
    private var meter: Double = 0
    private var conversionSeconds: Double = 0
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let values = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        guard accepting else { return }
        let count = min(Int(buffer.frameLength), (VoiceAudioSegmentation.maximumBytes - samples.count) / 4)
        guard count > 0 else { return }
        var energy: Float = 0
        for index in 0..<count { energy += values[index] * values[index] }
        let rms = sqrt(energy / Float(count))
        peak = max(peak, rms)
        meter = min(1, Double(rms) * 12)
        samples.append(UnsafeBufferPointer(start: values, count: count))
    }
    var sampleCount: Int { lock.lock(); defer { lock.unlock() }; return samples.count / 4 }
    var resamplingSeconds: Double { lock.lock(); defer { lock.unlock() }; return conversionSeconds }
    func recordConversion(seconds: Double) { lock.lock(); defer { lock.unlock() }; conversionSeconds += seconds }
    func preview(after offset: Int) -> Data? {
        lock.lock(); defer { lock.unlock() }
        let count = VoiceAudioSegmentation.previewSeconds * VoiceAudioSegmentation.sampleRate
        guard accepting, offset >= 0, offset <= samples.count / 4 - count else { return nil }
        return samples.subdata(in: (offset * 4)..<((offset + count) * 4))
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
    var sampleCount: Int { samples?.sampleCount ?? 0 }
    private(set) var resamplingSeconds: Double = 0
    func preview(after offset: Int) -> Data? { samples?.preview(after: offset) }
    func start() throws {
        cancel()
        resamplingSeconds = 0
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: output) else { throw VoiceFailure.unavailable }
        let samples = VoiceSamples()
        Self.installTap(on: input, processor: VoiceTapProcessor(input: format, output: output,
                                                                converter: converter, samples: samples))
        self.engine = engine; self.samples = samples
        do { try engine.start() } catch { cancel(); throw error }
    }
    func finish() -> Data {
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        resamplingSeconds = samples?.resamplingSeconds ?? 0
        let data = samples?.take() ?? Data()
        samples = nil
        return data
    }
    func cancel() { _ = finish() }

    /// Built outside the main actor: AVAudioEngine calls the tap on its realtime thread, and a
    /// closure formed in a @MainActor method would trap on Swift 6's isolation check.
    nonisolated private static func installTap(on input: AVAudioInputNode, processor: VoiceTapProcessor) {
        input.installTap(onBus: 0, bufferSize: 2048, format: processor.inputFormat) { buffer, _ in
            processor.process(buffer)
        }
    }
}

/// Converts tapped audio to 16 kHz mono on the audio thread. Converter state is only
/// touched from that one serial tap callback.
final class VoiceTapProcessor: @unchecked Sendable {
    let inputFormat: AVAudioFormat
    private let output: AVAudioFormat
    private let converter: AVAudioConverter
    private let samples: VoiceSamples
    fileprivate init(input: AVAudioFormat, output: AVAudioFormat, converter: AVAudioConverter, samples: VoiceSamples) {
        self.inputFormat = input; self.output = output; self.converter = converter; self.samples = samples
    }
    func process(_ buffer: AVAudioPCMBuffer) {
        let start = ProcessInfo.processInfo.systemUptime
        defer { samples.recordConversion(seconds: ProcessInfo.processInfo.systemUptime - start) }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / inputFormat.sampleRate)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
        let source = VoiceConversionInput(buffer)
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, state in source.provide(state) }
        if error == nil, status != .error { samples.append(converted) }
    }
    /// Test seam: a processor over synthetic formats, exercised from a background thread.
    static func forTesting(input: AVAudioFormat) -> (VoiceTapProcessor, () -> Data)? {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output) else { return nil }
        let samples = VoiceSamples()
        return (VoiceTapProcessor(input: input, output: output, converter: converter, samples: samples), { samples.take() })
    }
}
