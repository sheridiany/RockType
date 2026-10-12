import AppKit
import XCTest
import RoarkTCore
@testable import RoarkTApp

final class T5GestureTests: XCTestCase {
    func testScrollingCannotReviveAfterMoreDragging() {
        var gesture = SelectionGesture()
        gesture.begin(modifiers: [], suppress: true)
        gesture.drag(modifiers: [])
        gesture.scroll()
        gesture.drag(modifiers: [])
        XCTAssertFalse(gesture.finish(clickCount: 1, modifiers: []))
        gesture.begin(modifiers: [], suppress: true)
        gesture.drag(modifiers: [])
        XCTAssertTrue(gesture.finish(clickCount: 1, modifiers: []), "next ordinary gesture is independent")
        XCTAssertFalse(gesture.finish(clickCount: 2, modifiers: []), "mouse-up without a source mouse-down is ignored")
    }
    func testHeldAndMidGestureModifiersStaySuppressedUntilNextGesture() {
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command, .function] {
            var gesture = SelectionGesture()
            gesture.begin(modifiers: flag, suppress: true)
            gesture.drag(modifiers: [])
            XCTAssertFalse(gesture.finish(clickCount: 1, modifiers: []))
            gesture.begin(modifiers: [], suppress: true)
            gesture.drag(modifiers: [])
            gesture.modifiersChanged(flag)
            gesture.modifiersChanged([])
            XCTAssertFalse(gesture.finish(clickCount: 1, modifiers: []))
        }
        var gesture = SelectionGesture()
        gesture.begin(modifiers: .capsLock, suppress: true)
        XCTAssertTrue(gesture.finish(clickCount: 2, modifiers: .capsLock))
    }
    func testPreferenceAllowsModifiedScrollingGestureAndUnicodeLengthIsNotBytes() {
        var gesture = SelectionGesture()
        gesture.begin(modifiers: .option, suppress: false)
        gesture.drag(modifiers: .option); gesture.scroll()
        XCTAssertTrue(gesture.finish(clickCount: 1, modifiers: .option))
        for text in ["a", " 中 \n", "e\u{301}", "👩🏽‍💻"] {
            XCTAssertFalse(SelectionGesture.permitsText(text, suppress: true))
            XCTAssertTrue(SelectionGesture.permitsText(text, suppress: false))
        }
        XCTAssertTrue(SelectionGesture.permitsText("中文", suppress: true))
        XCTAssertTrue(SelectionGesture.permitsText("ab", suppress: true))
    }
    func testNewPreferencesRoundTripAndAbsentKeysKeepDefaults() throws {
        var settings = SelectionSettings()
        settings.toolbarIconsOnly = true; settings.suppressAccidentalPopups = false
        let encoded = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(SelectionSettings.self, from: encoded), settings)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "toolbarIconsOnly"); legacy.removeValue(forKey: "suppressAccidentalPopups")
        let restored = try JSONDecoder().decode(SelectionSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(restored.toolbarIconsOnly ?? false)
        XCTAssertTrue(restored.suppressAccidentalPopups ?? true)
    }
}
