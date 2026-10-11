import AppKit
import Carbon

@main
struct ModifierTests {
  static func main() {
    let raw = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    raw.type = .flagsChanged
    raw.flags = .maskShift
    let event = NSEvent(cgEvent: raw)!
    let cases: [(NSEvent.ModifierFlags, UInt16, Int32)] = [
      (.shift, event.keyCode, XK_Shift_L),
      (.shift, UInt16(kVK_RightShift), XK_Shift_R),
      (.shift, UInt16(kVK_Option), XK_Shift_L),  // coalesced Shift release + Option press
      (.option, UInt16(kVK_Option), XK_Alt_L),
      (.option, 0, XK_Alt_L),
      (.control, 0, XK_Control_L),
      (.command, 0, XK_Super_L),
      (.capsLock, 0, XK_Caps_Lock),
    ]
    for (flag, code, expected) in cases {
      let actual = SquirrelKeycode.modifierKeycode(modifier: flag, keycode: code)
      if actual != UInt32(expected) {
        fputs(
          "FAIL: flagsChanged keycode \(code) mapped to \(actual), expected modifier \(expected)\n",
          stderr)
        exit(1)
      }
    }
    precondition(
      SquirrelKeycode.osxKeycodeToRime(keycode: 0, keychar: "a", shift: false, caps: false)
        == UInt32(XK_a))
    print(
      "Modifier mapping passed: missing keycode, right Shift, coalesced transitions; ordinary A unchanged"
    )
  }
}
