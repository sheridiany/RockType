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
if let index = CommandLine.arguments.firstIndex(of: "--performance-dir"), CommandLine.arguments.indices.contains(index + 2) {
    do {
        let evaluation = try VoicePerformanceEvaluation(proxy: proxy, directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        let start = ProcessInfo.processInfo.systemUptime
        proxy.prepare(directory: CommandLine.arguments[index + 2]) { ready in
            guard ready else { finish(1) }
            let seconds = ProcessInfo.processInfo.systemUptime - start
            try? String(seconds).write(toFile: CommandLine.arguments[index + 1] + "/prepare-seconds.txt", atomically: true, encoding: .utf8)
            evaluation.next()
        }
    } catch { finish(1) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 900) { finish(1) }
} else if let index = CommandLine.arguments.firstIndex(of: "--evaluate-dir"), CommandLine.arguments.indices.contains(index + 2) {
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let model = CommandLine.arguments[index + 2]
    do {
        let evaluation = try VoiceAccuracyEvaluation(proxy: proxy, directory: directory)
        proxy.prepare(directory: model) { ready in
            guard ready else { finish(1) }
            evaluation.next()
        }
    } catch { finish(1) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 300) { finish(1) }
} else {
    // No model download, microphone, user content or real input target.
    proxy.prepare(directory: "/nonexistent-roarkt-voice-smoke-model") { @Sendable [expectRejection] ready in
        guard !expectRejection, !ready else { finish(1) }
        print("Signed XPC helper replied; invalid model rejected")
        finish(0)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("FAIL: XPC smoke timed out"); finish(1) }
}
dispatchMain()
