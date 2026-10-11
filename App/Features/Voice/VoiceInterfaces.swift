import Foundation

/// Local lifecycle interfaces. The wire contracts remain in Shared/XPCProtocol and VoiceWorkerProtocol.
enum VoiceFailure: Error { case timeout, unavailable, model, empty, permission }

@MainActor protocol VoiceRecognizing: AnyObject {
    func prepare(directory: URL) async throws
    func transcribe(_ audio: Data) async throws -> String
    func stop()
    func preview(_ audio: Data) async throws -> String
}

extension VoiceRecognizing {
    func preview(_ audio: Data) async throws -> String { try await transcribe(audio) }
}

struct VoiceTarget: Sendable {
    let token: String
    let applicationID: String
    let deadline: TimeInterval
}
@MainActor protocol VoiceCommitting: AnyObject {
    func capture(pid: Int32) async throws -> VoiceTarget
    func commit(_ text: String, target: VoiceTarget) async throws -> Bool
    func cancel(_ target: VoiceTarget?)
}
