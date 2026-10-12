// SPDX-License-Identifier: GPL-3.0-or-later
// Extracted from SquirrelInputController.swift (Leo Liu, 2024).
import Carbon
import InputMethodKit

/// Native key ordering, Rime key dispatch and chord handling. State remains owned by the controller.
extension SquirrelInputController {
  func handleInputEvent(_ event: NSEvent?, sender: Any?) -> Bool {
    guard let event = event else { return false }
    let modifiers = event.modifierFlags
    let changes = lastModifiers.symmetricDifference(modifiers)

    // Return true to indicate the the key input was received and dealt with.
    // Key processing will not continue in that case.  In other words the
    // system will not deliver a key down event to the application.
    // Returning false means the original key down will be passed on to the client.
    var handled = false
    if session == 0 || !rimeAPI.find_session(session) {
      createSession()
      if session == 0 {
        return false
      }
    }

    self.client ?= sender as? IMKTextInput
    if let app = client?.bundleIdentifier(), currentApp != app {
      currentApp = app
      updateAppOptions()
    }

    switch event.type {
    case .flagsChanged:
      if lastModifiers == modifiers {
        handled = true
        break
      }
      var rimeModifiers: UInt32 = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)
      if changes.contains(.capsLock) {
        let rimeKeycode = SquirrelKeycode.modifierKeycode(modifier: .capsLock, keycode: event.keyCode)
        // NOTE: rime assumes XK_Caps_Lock to be sent before modifier changes,
        // while NSFlagsChanged event has the flag changed already.
        // so it is necessary to revert kLockMask.
        rimeModifiers ^= kLockMask.rawValue
        _ = processKey(rimeKeycode, modifiers: rimeModifiers)
      }

      // Need to process release before modifier down. Because
      // sometimes release event is delayed to next modifier keydown.
      var buffer = [(keycode: UInt32, modifier: UInt32)]()
      for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] where changes.contains(flag) {
        let rimeKeycode = SquirrelKeycode.modifierKeycode(modifier: flag, keycode: event.keyCode)
        if modifiers.contains(flag) { // New modifier
          buffer.append((keycode: rimeKeycode, modifier: rimeModifiers))
        } else { // Release
          buffer.insert((keycode: rimeKeycode, modifier: rimeModifiers | kReleaseMask.rawValue), at: 0)
        }
      }
      for (keycode, modifier) in buffer {
        _ = processKey(keycode, modifiers: modifier)
      }

      lastModifiers = modifiers
      rimeUpdate()

    case .keyDown:
      translationClient.noteInputActivity()
      inputModePanel.hide()
      let keyCode = event.keyCode
      if matchesInputAIShortcut(event), inputPreferences.allowsInputAI,
         let snapshot = translationSnapshot(forAI: true) {
        if !event.isARepeat { sendInputAI(candidateTranslation.beginAI(snapshot)) }
        handled = true
        break
      }
      if keyCode == 53, candidateTranslation.ticket?.action != nil {
        cancelDynamicTranslation()
        requestDynamicTranslationIfNeeded()
        handled = true // First Escape dismisses AI; leave Rime composition intact.
        break
      }
      // Other Command shortcuts belong to the source app; revoke any AI result first.
      if modifiers.contains(.command) {
        if candidateTranslation.ticket?.action != nil { cancelDynamicTranslation() }
        break
      }
      if keyCode == 48, modifiers.isDisjoint(with: [.control, .option, .command, .shift]),
         candidateTranslation.interceptsTab {
        if !event.isARepeat { performTranslationAction() }
        handled = true // Never submit a stale result or move app focus while loading.
        break
      }
      if candidateTranslation.ticket?.action != nil { cancelDynamicTranslation() }
      var keyChars = event.charactersIgnoringModifiers
      let capitalModifiers = modifiers.isSubset(of: [.shift, .capsLock])
      if let code = keyChars?.first,
         (capitalModifiers && !code.isLetter) || (!capitalModifiers && !code.isASCII) {
        keyChars = event.characters
      }

      // translate osx keyevents to rime keyevents
      if let char = keyChars?.first {
        let rimeKeycode = SquirrelKeycode.osxKeycodeToRime(keycode: keyCode, keychar: char,
                                                           shift: modifiers.contains(.shift),
                                                           caps: modifiers.contains(.capsLock))
        if rimeKeycode != 0 {
          let rimeModifiers = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
          rimeUpdate()
        }
      }

    default:
      break
    }

    // Reaching this controller proves the native IMK input path is active,
    // even when Rime intentionally passes digits or punctuation through.
    if event.type == .keyDown, !IsSecureEventInputEnabled() {
      translationClient.recordControllerInput()
      NSApp.squirrelAppDelegate.inputControllerDidHandleKeyDown(self)
    }
    return handled
  }

  func onChordTimer() {
    // chord release triggered by timer
    var processedKeys = false
    if chordKeyCount > 0 && session != 0 {
      // simulate key-ups
      for i in 0..<chordKeyCount {
        let handled = rimeAPI.process_key(session, Int32(chordKeyCodes[i]), Int32(chordModifiers[i] | kReleaseMask.rawValue))
        if handled {
          processedKeys = true
        }
      }
    }
    clearChord()
    if processedKeys {
      rimeUpdate()
    }
  }

  func updateChord(keycode: UInt32, modifiers: UInt32) {
    for i in 0..<chordKeyCount where chordKeyCodes[i] == keycode {
      return
    }
    if chordKeyCount >= Self.keyRollOver {
      // you are cheating. only one human typist (fingers <= 10) is supported.
      return
    }
    chordKeyCodes[chordKeyCount] = keycode
    chordModifiers[chordKeyCount] = modifiers
    chordKeyCount += 1
    // reset timer
    if let timer = chordTimer, timer.isValid {
      timer.invalidate()
    }
    chordDuration = 0.1
    if let duration = NSApp.squirrelAppDelegate.config?.getDouble("chord_duration"), duration > 0 {
      chordDuration = duration
    }
    chordTimer = Timer.scheduledTimer(withTimeInterval: chordDuration, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.onChordTimer() }
    }
  }

  func clearChord() {
    chordKeyCount = 0
    if let timer = chordTimer {
      if timer.isValid {
        timer.invalidate()
      }
      chordTimer = nil
    }
  }

  func processKey(_ rimeKeycode: UInt32, modifiers rimeModifiers: UInt32) -> Bool {
    if !inputPreferences.input.shiftTogglesLanguage && (rimeKeycode == XK_Shift_L || rimeKeycode == XK_Shift_R) {
      return false
    }

    // with linear candidate list, arrow keys may behave differently.
    if let panel = NSApp.squirrelAppDelegate.panel {
      if panel.linear != rimeAPI.get_option(session, "_linear") {
        rimeAPI.set_option(session, "_linear", panel.linear)
      }
      // with vertical text, arrow keys may behave differently.
      if panel.vertical != rimeAPI.get_option(session, "_vertical") {
        rimeAPI.set_option(session, "_vertical", panel.vertical)
      }
    }

    let handled = rimeAPI.process_key(session, Int32(rimeKeycode), Int32(rimeModifiers))

    // TODO add special key event postprocessing here

    if !handled {
      let isVimBackInCommandMode = rimeKeycode == XK_Escape || ((rimeModifiers & kControlMask.rawValue != 0) && (rimeKeycode == XK_c || rimeKeycode == XK_C || rimeKeycode == XK_bracketleft))
      if isVimBackInCommandMode && rimeAPI.get_option(session, "vim_mode") &&
          !rimeAPI.get_option(session, "ascii_mode") {
        rimeAPI.set_option(session, "ascii_mode", true)
      }
    } else {
      let isChordingKey = switch Int32(rimeKeycode) {
      case XK_space...XK_asciitilde, XK_Control_L, XK_Control_R, XK_Alt_L, XK_Alt_R, XK_Shift_L, XK_Shift_R:
        true
      default:
        false
      }
      if isChordingKey && rimeAPI.get_option(session, "_chord_typing") {
        updateChord(keycode: rimeKeycode, modifiers: rimeModifiers)
      } else if (rimeModifiers & kReleaseMask.rawValue) == 0 {
        // non-chording key pressed
        clearChord()
      }
    }

    return handled
  }

  func matchesInputAIShortcut(_ event: NSEvent) -> Bool {
    guard let shortcut = inputPreferences.input.inputAI?.shortcut else { return false }
    var modifiers: Shortcut.Modifiers = []
    for (native, configured) in [(NSEvent.ModifierFlags.control, Shortcut.Modifiers.control),
                                (.option, .option), (.command, .command), (.shift, .shift)] {
      if event.modifierFlags.contains(native) { modifiers.insert(configured) }
    }
    return RoarkTInputAIAction.matches(keyCode: event.keyCode, modifiers: modifiers, shortcut: shortcut)
  }
}
