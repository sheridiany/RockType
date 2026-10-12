import Foundation
import ObjectiveC
import Testing
@testable import RoarkTApp

@Test func voiceWorkerWireSelectorsRemainStable() throws {
    let wire = try #require(objc_getProtocol("RoarkTVoiceWorkerProtocol"))
    #expect(String(cString: protocol_getName(wire)) == "RoarkTVoiceWorkerProtocol")
    var count: UInt32 = 0
    let methods = try #require(protocol_copyMethodDescriptionList(wire, true, true, &count))
    defer { free(methods) }
    let selectors = (0..<Int(count)).compactMap { methods[$0].name.map(NSStringFromSelector) }
    #expect(Set(selectors) == ["prepareWithDirectory:reply:", "transcribeWithAudio:context:reply:", "shutdown"])
    #expect(NSStringFromSelector(#selector(VoiceWorkerProtocol.prepare(directory:reply:))) == "prepareWithDirectory:reply:")
    #expect(NSStringFromSelector(#selector(VoiceWorkerProtocol.transcribe(audio:context:reply:))) == "transcribeWithAudio:context:reply:")
    let interface = NSXPCInterface(with: VoiceWorkerProtocol.self)
    #expect(protocol_isEqual(interface.protocol, wire))
}

@Test func voiceWorkerCancellationSkipsProcessGlobalDestructors() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RockType-worker-shutdown-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("shutdown-check")
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    compiler.arguments = ["swiftc", "-swift-version", "6", "-parse-as-library",
        root.appendingPathComponent("Services/VoiceWorker/Sources/RoarkTVoiceWorker/WorkerTermination.swift").path,
        root.appendingPathComponent("Tests/VoiceWorkerSmoke/Shutdown.swift").path, "-o", executable.path]
    try compiler.run(); compiler.waitUntilExit()
    try #require(compiler.terminationStatus == 0)
    let process = Process()
    process.executableURL = executable
    try process.run(); process.waitUntilExit()
    #expect(process.terminationReason == .exit)
    #expect(process.terminationStatus == 0, "XPC cancellation must not run destructors concurrently with inference (sentinel exit 99)")
}
