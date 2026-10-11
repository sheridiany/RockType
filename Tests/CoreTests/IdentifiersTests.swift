import Foundation
import Testing
@testable import RoarkTCore

@Test func swiftIdentifiersMatchObjCHeader() throws {
    let header = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Shared/XPCProtocol/include/RoarkTIdentifiers.h")
    let text = try String(contentsOf: header, encoding: .utf8)
    for value in [Identifiers.teamID, Identifiers.appBundleID, Identifiers.inputMethodBundleID,
                  Identifiers.translationServiceName, Identifiers.voiceWorkerID,
                  Identifiers.dictationEndpointName] {
        #expect(text.contains("@\"\(value)\""), "missing \(value) in RoarkTIdentifiers.h")
    }
}

@Test func defaultShortcutsFollowADR0002() {
    #expect(Shortcut.defaults[.voiceHoldToTalk] == Shortcut(key: nil, modifiers: .function))
    #expect(Shortcut.defaults[.screenshot] == Shortcut(key: "1", modifiers: .control))
    #expect(Shortcut.defaults.count == ShortcutAction.allCases.count)
}
