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
