import XCTest
import Carbon
import RoarkTCore
@testable import RoarkTPlatform

final class ShortcutTests: XCTestCase {
    @MainActor func testDefaultsHaveCarbonBindingsExceptFn() throws {
        let screenshot = try GlobalHotkeys.binding(try XCTUnwrap(Shortcut.defaults[.screenshot]))
        XCTAssertEqual(screenshot.key, UInt32(kVK_ANSI_1))
        XCTAssertEqual(screenshot.modifiers, UInt32(controlKey))
        let translate = try GlobalHotkeys.binding(try XCTUnwrap(Shortcut.defaults[.translateSelection]))
        XCTAssertEqual(translate.key, UInt32(kVK_ANSI_T))
        XCTAssertEqual(translate.modifiers, UInt32(controlKey | optionKey))
        let summarize = try GlobalHotkeys.binding(try XCTUnwrap(Shortcut.defaults[.summarizeSelection]))
        XCTAssertEqual(summarize.key, UInt32(kVK_ANSI_S))
        XCTAssertThrowsError(try GlobalHotkeys.binding(try XCTUnwrap(Shortcut.defaults[.voiceHoldToTalk]))) {
            XCTAssertEqual($0 as? GlobalHotkeys.Failure, .unsupportedShortcut)
        }
        XCTAssertThrowsError(try GlobalHotkeys.binding(Shortcut(key: "unknown", modifiers: .control)))
    }

    func testShortTapDoesNotStartOrRelease() {
        var gesture = FnGesture()
        XCTAssertEqual(gesture.flags(fn: true, keyCode: 63, otherModifiers: false, allowed: true), .none)
        XCTAssertEqual(gesture.flags(fn: false, keyCode: 63, otherModifiers: false, allowed: true), .none)
        XCTAssertEqual(gesture.holdElapsed(), .none)
    }

    func testHoldReleasesExactlyOnce() {
        var gesture = FnGesture()
        _ = gesture.flags(fn: true, keyCode: 63, otherModifiers: false, allowed: true)
        XCTAssertEqual(gesture.holdElapsed(), .press)
        XCTAssertEqual(gesture.holdElapsed(), .none)
        XCTAssertEqual(gesture.flags(fn: false, keyCode: 63, otherModifiers: false, allowed: true), .release)
        XCTAssertEqual(gesture.flags(fn: false, keyCode: 63, otherModifiers: false, allowed: true), .none)
    }

    func testChordCancelsWithoutRestartOrRelease() {
        var gesture = FnGesture()
        _ = gesture.flags(fn: true, keyCode: 63, otherModifiers: false, allowed: true)
        _ = gesture.holdElapsed()
        XCTAssertEqual(gesture.flags(fn: true, keyCode: 56, otherModifiers: true, allowed: true), .cancel)
        _ = gesture.flags(fn: true, keyCode: 56, otherModifiers: false, allowed: true)
        XCTAssertEqual(gesture.holdElapsed(), .none)
        XCTAssertEqual(gesture.flags(fn: false, keyCode: 63, otherModifiers: false, allowed: true), .none)
    }

    func testChordAndDisallowedInputNeverStart() {
        for (key, modifiers, allowed) in [(63, true, true), (63, false, false), (126, false, true)] {
            var gesture = FnGesture()
            _ = gesture.flags(fn: true, keyCode: key, otherModifiers: modifiers, allowed: allowed)
            XCTAssertEqual(gesture.holdElapsed(), .none)
        }
    }

    func testSecureInputAtReleaseCancels() {
        var gesture = FnGesture()
        _ = gesture.flags(fn: true, keyCode: 0, otherModifiers: false, allowed: true)
        XCTAssertEqual(gesture.holdElapsed(), .press)
        XCTAssertEqual(gesture.flags(fn: false, keyCode: 0, otherModifiers: false, allowed: false), .cancel)
    }

    func testInteractionAndStopCancelPendingHold() {
        var gesture = FnGesture()
        _ = gesture.flags(fn: true, keyCode: 63, otherModifiers: false, allowed: true)
        XCTAssertEqual(gesture.cancel(), .none)
        XCTAssertEqual(gesture.holdElapsed(), .none)
        gesture.reset()
        _ = gesture.flags(fn: true, keyCode: 63, otherModifiers: false, allowed: true)
        XCTAssertEqual(gesture.holdElapsed(), .press)
        XCTAssertEqual(gesture.cancel(), .cancel)
        XCTAssertEqual(gesture.cancel(), .none)
    }
}
