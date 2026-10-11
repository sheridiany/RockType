import Foundation
let expectRejection = CommandLine.arguments.contains("--reject")
let connection = NSXPCConnection(serviceName: Identifiers.voiceWorkerID)
connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.voiceWorkerID))
connection.remoteObjectInterface = NSXPCInterface(with: VoiceWorkerProtocol.self)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable [expectRejection] _ in
    print(expectRejection ? "Unauthorized caller rejected" : "FAIL: signed XPC connection failed")
    exit(expectRejection ? 0 : 1)
} as! VoiceWorkerProtocol
// No model download, microphone, user content or real input target.
proxy.prepare(directory: "/nonexistent-roarkt-voice-smoke-model") { @Sendable [expectRejection] ready in
    guard !expectRejection, !ready else { exit(1) }
    print("Signed XPC helper replied; invalid model rejected")
    exit(0)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("FAIL: XPC smoke timed out"); exit(1) }
dispatchMain()
