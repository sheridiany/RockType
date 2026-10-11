import Foundation

/// Private App ↔ MLX service contract. Audio is mono Float32 little-endian, 16 kHz,
/// bounded to 60 seconds; neither process persists audio or recognition contents.
@objc(RoarkTVoiceWorkerProtocol)
protocol VoiceWorkerProtocol {
    func prepare(directory: String, reply: @escaping (Bool) -> Void)
    func transcribe(audio: Data, context: String, reply: @escaping (String?) -> Void)
    func shutdown()
}
