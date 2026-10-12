import AppKit
import Testing
@testable import RoarkTApp

@MainActor @Test func voiceCapsuleFollowsActiveScreenAboveDockWithoutTakingFocus() {
    var screen = NSRect(x: 0, y: 80, width: 1440, height: 800)
    var panel: NSPanel?
    let hud = RoarkTVoiceHUD(present: { panel = $0 }, reduceMotion: { true }, visibleFrame: { screen })
    hud.show(.recording)
    #expect(panel?.frame.midX == screen.midX)
    #expect(panel?.frame.minY == screen.minY + 16)
    screen = NSRect(x: -1920, y: -300, width: 1920, height: 1000)
    hud.updateRecording(decibels: -20)
    #expect(panel?.frame.midX == screen.midX)
    #expect(panel?.frame.minY == screen.minY + 16)
    #expect(panel?.canBecomeKey == false && panel?.canBecomeMain == false)
    hud.show(.result("合成文字"))
    #expect(panel?.frame.midX == screen.midX)
    #expect(screen.contains(panel!.frame))
    hud.hide()
}
