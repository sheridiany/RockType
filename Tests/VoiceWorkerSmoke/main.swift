import Foundation
func finish(_ status: Int32) -> Never {
    if let index = CommandLine.arguments.firstIndex(of: "--status-file"), CommandLine.arguments.indices.contains(index + 1) {
        do { try String(status).write(toFile: CommandLine.arguments[index + 1], atomically: true, encoding: .utf8) }
        catch { exit(2) }
    }
    exit(status)
}
let expectRejection = CommandLine.arguments.contains("--reject")
let connection = NSXPCConnection(serviceName: Identifiers.voiceWorkerID)
connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.voiceWorkerID))
connection.remoteObjectInterface = NSXPCInterface(with: VoiceWorkerProtocol.self)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable [expectRejection] _ in
    print(expectRejection ? "Unauthorized caller rejected" : "FAIL: signed XPC connection failed")
    finish(expectRejection ? 0 : 1)
} as! VoiceWorkerProtocol
// No model download, microphone, user content or real input target.
proxy.prepare(directory: "/nonexistent-roarkt-voice-smoke-model") { @Sendable [expectRejection] ready in
    guard !expectRejection, !ready else { finish(1) }
    print("Signed XPC helper replied; invalid model rejected")
    finish(0)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("FAIL: XPC smoke timed out"); finish(1) }
dispatchMain()
