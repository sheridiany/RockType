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

@Test func settingsWithoutMenuBarFieldDecodeWithItemHidden() throws {
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.defaults)) as! [String: Any]
    var general = legacy["general"] as! [String: Any]
    general.removeValue(forKey: "menuBarIcon")
    legacy["general"] = general
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(decoded.general.menuBarIcon == nil && !decoded.general.showsMenuBarItem)
    var clock = decoded.general; clock.showBeijingTime = true
    #expect(clock.showsMenuBarItem)
}
