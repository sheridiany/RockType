//
//  SquirrelInputController.swift
//  Squirrel
//
//  Created by Leo Liu on 5/7/24.
//

import Carbon
import InputMethodKit

// IMK callbacks predate Swift concurrency and are synchronous on the main run loop.
// Each override asserts that boundary before touching actor-owned state. The local
// unsafe bindings only bridge ObjC arguments within the same synchronous call.
@MainActor
final class SquirrelInputController: IMKInputController, @unchecked Sendable {
  nonisolated private static let keyRollOver = 50

  private weak var client: IMKTextInput?
  private let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  private var preedit: String = ""
  private var selRange: NSRange = .empty
  private var caretPos: Int = 0
  private var lastModifiers: NSEvent.ModifierFlags = .init()
  private var session: RimeSessionId = 0
  private var schemaId: String = ""
  private var selectedSchema = "roarkt"
  private var inlinePreedit = false
  private var inlineCandidate = false
  // for chord-typing
  private var chordKeyCodes: [UInt32] = .init(repeating: 0, count: SquirrelInputController.keyRollOver)
  private var chordModifiers: [UInt32] = .init(repeating: 0, count: SquirrelInputController.keyRollOver)
  private var chordKeyCount: Int = 0
  private var chordTimer: Timer?
  private var chordDuration: TimeInterval = 0
  private var currentApp: String = ""
  private var visibleCandidates = [String]()
  private var visiblePageSize = 0
  private let propertyReader = RoarkTRimePropertyReader()
  private let translationClient = RoarkTTranslationClient()
  private let translationSessionID = UUID().uuidString
  private var candidateTranslation = RoarkTCandidateTranslationSession()
  private var translationLoadingTimer: DispatchWorkItem?
  private var lastTranslationError: String?
  // IMK invokes this controller on the main run loop; assert that boundary.
  private lazy var inputModePanel = MainActor.assumeIsolated { RoarkTInputModePanel() }

  var voiceClient: IMKTextInput? {
    guard preedit.isEmpty, !IsSecureEventInputEnabled() else { return nil }
    return client
  }

  // swiftlint:disable:next cyclomatic_complexity
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    nonisolated(unsafe) let event = event
    nonisolated(unsafe) let sender = sender
    return MainActor.assumeIsolated {
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
        // ignore Command+X hotkeys.
        if modifiers.contains(.command) {
          break
        }

        let keyCode = event.keyCode
        if keyCode == 48, modifiers.isDisjoint(with: [.control, .option, .command, .shift]),
           candidateTranslation.interceptsTab {
          if !event.isARepeat { performTranslationAction() }
          handled = true // Never submit a stale result or move app focus while loading.
          break
        }
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
  }

  func highlightCandidate(_ index: Int) {
    guard session != 0, rimeAPI.highlight_candidate_on_current_page(session, index) else { return }
    rimeUpdate()
  }

  func performTranslationAction() {
    if candidateTranslation.canRetry {
      guard translationSnapshot() == candidateTranslation.ticket?.snapshot,
            let request = candidateTranslation.retry() else { return }
      sendTranslation(request)
    } else {
      commitTranslationSelection()
    }
  }

  func learningMenu(for index: Int) -> NSMenu? {
    guard session != 0, visibleCandidates.indices.contains(index) else { return nil }
    highlightCandidate(index)
    guard let context = translationContext(),
          context.snapshot.isSelected(index: index, pageSize: visiblePageSize) else { return nil }
    let snapshot = context.snapshot
    let sessionId = session
    return RoarkTCandidateLearningMenu.make(candidate: visibleCandidates[index],
      canForget: context.canForget) { [weak self] in
      guard let self, self.session == sessionId, let current = self.translationContext(),
            current.snapshot == snapshot, current.canForget else { return }
      self.cancelDynamicTranslation()
      _ = self.rimeAPI.delete_candidate_on_current_page(self.session, index)
      self.rimeUpdate()
    }
  }

  func selectCandidate(_ index: Int) -> Bool {
    let success = rimeAPI.select_candidate_on_current_page(session, index)
    if success {
      rimeUpdate()
    }
    return success
  }

  // swiftlint:disable:next identifier_name
  func page(up: Bool) -> Bool {
    var handled = false
    handled = rimeAPI.change_page(session, up)
    if handled {
      rimeUpdate()
    }
    return handled
  }

  func moveCaret(forward: Bool) -> Bool {
    let currentCaretPos = rimeAPI.get_caret_pos(session)
    guard let input = rimeAPI.get_input(session) else { return false }
    if forward {
      if currentCaretPos <= 0 {
        return false
      }
      rimeAPI.set_caret_pos(session, currentCaretPos - 1)
    } else {
      let inputStr = String(cString: input)
      if currentCaretPos >= inputStr.utf8.count {
        return false
      }
      rimeAPI.set_caret_pos(session, currentCaretPos + 1)
    }
    rimeUpdate()
    return true
  }

  override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
    nonisolated(unsafe) let value = value
    nonisolated(unsafe) let sender = sender
    return MainActor.assumeIsolated {
      super.setValue(value, forTag: tag, client: sender)
      guard tag == Int(kTextServiceInputModePropertyTag), let identifier = value as? String else { return }
      let schema: String
      switch identifier {
      case "com.roarkist.inputmethod.RoarkT.pinyin": schema = "roarkt"
      case "com.roarkist.inputmethod.RoarkT.flypy": schema = "roarkt_flypy"
      default: return
      }
      selectedSchema = schema
      if session != 0 {
        cancelDynamicTranslation()
        _ = rimeAPI.select_schema(session, schema)
        rimeUpdate()
      }
    }
  }

  override func recognizedEvents(_ sender: Any!) -> Int {
    return MainActor.assumeIsolated {
      return Int(NSEvent.EventTypeMask.Element(arrayLiteral: .keyDown, .flagsChanged).rawValue)
    }
  }

  override func activateServer(_ sender: Any!) {
    nonisolated(unsafe) let sender = sender
    return MainActor.assumeIsolated {
      cancelDynamicTranslation() // Activation starts a new presentation/composition boundary.
      self.client ?= sender as? IMKTextInput
      var keyboardLayout = NSApp.squirrelAppDelegate.config?.getString("keyboard_layout") ?? ""
      if keyboardLayout == "last" || keyboardLayout == "" {
        keyboardLayout = ""
      } else if keyboardLayout == "default" {
        keyboardLayout = "com.apple.keylayout.ABC"
      } else if !keyboardLayout.hasPrefix("com.apple.keylayout.") {
        keyboardLayout = "com.apple.keylayout.\(keyboardLayout)"
      }
      if keyboardLayout != "" {
        client?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
      }
      translationClient.activate()
      preedit = ""
      lastModifiers = NSEvent.modifierFlags
      if let app = client?.bundleIdentifier(), currentApp != app {
        currentApp = app
        updateAppOptions()
      }
      NSApp.squirrelAppDelegate.inputControllerDidActivate(self)
      inputModePanel.activate(client: client, ascii: rimeAPI.get_option(session, "ascii_mode"))
    }
  }

  override init!(server: IMKServer!, delegate: Any!, client: Any!) {
    super.init(server: server, delegate: delegate, client: client)
    nonisolated(unsafe) let client = client
    MainActor.assumeIsolated {
      self.client = client as? IMKTextInput
      createSession()
    }
  }

  override func deactivateServer(_ sender: Any!) {
    nonisolated(unsafe) let sender = sender
    return MainActor.assumeIsolated {
      NSApp.squirrelAppDelegate.inputControllerDidDeactivate(self)
      inputModePanel.deactivate()
      cancelDynamicTranslation()
      hidePalettes()
      commitComposition(sender)
      translationClient.deactivate()
      client = nil
    }
  }

  override func hidePalettes() {
    return MainActor.assumeIsolated {
      inputModePanel.hide()
      NSApp.squirrelAppDelegate.panel?.hide()
      super.hidePalettes()
    }
  }

  // End the input session and send its current buffer to the client.
  override func commitComposition(_ sender: Any!) {
    nonisolated(unsafe) let sender = sender
    return MainActor.assumeIsolated {
      cancelDynamicTranslation()
      self.client ?= sender as? IMKTextInput
      //  commit raw input
      if session != 0 {
        if let input = rimeAPI.get_input(session) {
          commit(string: String(cString: input))
          rimeAPI.clear_composition(session)
        }
      }
    }
  }

  override func menu() -> NSMenu! {
    // IMK synchronously consumes the menu on this same main-thread call.
    nonisolated(unsafe) var result: NSMenu?
    MainActor.assumeIsolated {
      let deploy = NSMenuItem(title: NSLocalizedString("Deploy", comment: "Menu item"), action: #selector(deploy), keyEquivalent: "`")
      deploy.target = self
      deploy.keyEquivalentModifierMask = [.control, .option]
      let sync = NSMenuItem(title: NSLocalizedString("Sync user data", comment: "Menu item"), action: #selector(syncUserData), keyEquivalent: "")
      sync.target = self
      let logDir = NSMenuItem(title: NSLocalizedString("Logs...", comment: "Menu item"), action: #selector(openLogFolder), keyEquivalent: "")
      logDir.target = self
      let setting = NSMenuItem(title: NSLocalizedString("Settings...", comment: "Menu item"), action: #selector(openRimeFolder), keyEquivalent: "")
      setting.target = self
      let roarkTSettings = NSMenuItem(title: "打开RoarkT设置…", action: #selector(openRoarkTSettings), keyEquivalent: "")
      roarkTSettings.target = self
      roarkTSettings.isEnabled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ROARKT_APP_BUNDLE_ID) != nil

      let menu = NSMenu()
      menu.autoenablesItems = false
      menu.addItem(deploy)
      menu.addItem(sync)
      menu.addItem(logDir)
      menu.addItem(setting)
      menu.addItem(.separator())
      menu.addItem(roarkTSettings)

      result = menu
    }
    return result
  }

  @objc func deploy() {
    NSApp.squirrelAppDelegate.deploy()
  }

  @objc func syncUserData() {
    NSApp.squirrelAppDelegate.syncUserData()
  }

  @objc func openLogFolder() {
    NSApp.squirrelAppDelegate.openLogFolder()
  }

  @objc func openRimeFolder() {
    NSApp.squirrelAppDelegate.openRimeFolder()
  }

  @objc func openRoarkTSettings() {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ROARKT_APP_BUNDLE_ID) else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.arguments = ["--show-settings"]
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
  }

  isolated deinit {
    translationClient.invalidate()
    destroySession()
  }
}

private extension SquirrelInputController {
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

  func createSession() {
    let app = client?.bundleIdentifier() ?? "UnknownApp\(UUID().uuidString)"
    print("createSession: \(app)")
    currentApp = app
    session = rimeAPI.create_session()
    schemaId = ""

    if session != 0 {
      _ = rimeAPI.select_schema(session, selectedSchema)
      setTranslationProperty("roarkt_translation_presentation", "panel")
      updateAppOptions()
    }
  }

  func updateAppOptions() {
    if currentApp == "" {
      return
    }
    if let appOptions = NSApp.squirrelAppDelegate.config?.getAppOptions(currentApp) {
      for (key, value) in appOptions {
        print("set app option: \(key) = \(value)")
        rimeAPI.set_option(session, key, value)
      }
    }
  }

  func destroySession() {
    if session != 0 {
      let sessionID = translationSessionID
      translationClient.cancel(sessionID: sessionID, throughGeneration: candidateTranslation.ticket?.generation ?? 0)
      _ = rimeAPI.destroy_session(session)
      session = 0
    }
    candidateTranslation.invalidate()
    clearChord()
  }

  func processKey(_ rimeKeycode: UInt32, modifiers rimeModifiers: UInt32) -> Bool {
    // TODO add special key event preprocessing here

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

  func rimeConsumeCommittedText() {
    var commitText = RimeCommit.rimeStructInit()
    if rimeAPI.get_commit(session, &commitText) {
      if let text = commitText.text {
        commit(string: String(cString: text))
      }
      _ = rimeAPI.free_commit(&commitText)
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func rimeUpdate() {
    defer { inputModePanel.update(ascii: rimeAPI.get_option(session, "ascii_mode")) }
    rimeConsumeCommittedText()

    var status = RimeStatus_stdbool.rimeStructInit()
    if rimeAPI.get_status(session, &status) {
      // enable schema specific ui style
      // swiftlint:disable:next identifier_name
      if let schema_id = status.schema_id, schemaId == "" || schemaId != String(cString: schema_id) {
        schemaId = String(cString: schema_id)
        NSApp.squirrelAppDelegate.loadSettings(for: schemaId)
        // inline preedit
        if let panel = NSApp.squirrelAppDelegate.panel {
          inlinePreedit = (panel.inlinePreedit && !rimeAPI.get_option(session, "no_inline")) || rimeAPI.get_option(session, "inline")
          inlineCandidate = panel.inlineCandidate && !rimeAPI.get_option(session, "no_inline")
          // if not inline, embed soft cursor in preedit string
          rimeAPI.set_option(session, "soft_cursor", !inlinePreedit)
        }
      }
      _ = rimeAPI.free_status(&status)
    }

    var ctx = RimeContext_stdbool.rimeStructInit()
    if rimeAPI.get_context(session, &ctx) {
      // update preedit text
      let preedit = ctx.composition.preedit.map({ String(cString: $0) }) ?? ""

      let start = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_start)), within: preedit) ?? preedit.startIndex
      let end = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_end)), within: preedit) ?? preedit.startIndex
      let caretPos = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.cursor_pos)), within: preedit) ?? preedit.startIndex

      if inlineCandidate {
        var candidatePreview = ctx.commit_text_preview.map { String(cString: $0) } ?? ""
        let endOfCandidatePreview = candidatePreview.endIndex
        if inlinePreedit {
          // 左移光標後的情形：
          // preedit:             ^已選某些字[xiang zuo yi dong]|guangbiao$
          // commit_text_preview: ^已選某些字向左移動$
          // candidate_preview:   ^已選某些字[向左移動]|guangbiao$
          // 繼續翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
          // commit_text_preview: ^已選某些字向左yidong$
          // candidate_preview:   ^已選某些字[向左]yidong|guangbiao$
          // 光標移至當前段落最左端的情形：
          // preedit:             ^已選某些字|[xiang zuo yi dong guang biao]$
          // commit_text_preview: ^已選某些字向左移動光標$
          // candidate_preview:   ^已選某些字|[向左移動光標]$
          // 討論：
          // preedit 與 commit_text_preview 中“已選某些字”部分一致
          // 因此，選中範圍即正在翻譯的碼段“向左移動”中，兩者的 start 值一致
          // 光標位置的範圍是 start ..= endOfCandidatePreview
          if caretPos >= end && caretPos < preedit.endIndex {
            // 從 preedit 截取光標後未翻譯的編碼“guangbiao”
            candidatePreview += preedit[caretPos...]
          }
        } else {
          // 翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
          // commit_text_preview: ^已選某些字向左yidongguangbiao$
          // candidate_preview:   ^已選某些字[向左???]|$
          // 光標移至當前段落最左端，繼續翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字|[xiang zuo]yidongguangbiao$
          // commit_text_preview: ^已選某些字向左yidongguangbiao$
          // candidate_preview:   ^已選某些字|[向左]???$
          // FIXME: add librime APIs to support preview candidate without remaining code.
        }
        // preedit can contain additional prompt text before start:
        // ^(prompt)[selection]$
        let start = min(start, candidatePreview.endIndex)
        // caret can be either before or after the selected range.
        let caretPos = caretPos <= start ? caretPos : endOfCandidatePreview
        show(preedit: candidatePreview,
             selRange: NSRange(location: start.utf16Offset(in: candidatePreview),
                               length: candidatePreview.utf16.distance(from: start, to: candidatePreview.endIndex)),
             caretPos: caretPos.utf16Offset(in: candidatePreview))
      } else {
        if inlinePreedit {
          show(preedit: preedit, selRange: NSRange(location: start.utf16Offset(in: preedit), length: preedit.utf16.distance(from: start, to: end)), caretPos: caretPos.utf16Offset(in: preedit))
        } else {
          // TRICKY: display a non-empty string to prevent iTerm2 from echoing
          // each character in preedit. note this is a full-shape space U+3000;
          // using half shape characters like "..." will result in an unstable
          // baseline when composing Chinese characters.
          show(preedit: preedit.isEmpty ? "" : "　", selRange: NSRange(location: 0, length: 0), caretPos: 0)
        }
      }

      // update candidates
      let numCandidates = Int(ctx.menu.num_candidates)
      var candidates = [String]()
      var comments = [String]()
      for i in 0..<numCandidates {
        let candidate = ctx.menu.candidates[i]
        candidates.append(candidate.text.map { String(cString: $0) } ?? "")
        comments.append(candidate.comment.map { String(cString: $0) } ?? "")
      }
      var labels = [String]()
      // swiftlint:disable identifier_name
      if let select_keys = ctx.menu.select_keys {
        labels = String(cString: select_keys).map { String($0) }
      } else if let select_labels = ctx.select_labels {
        let pageSize = Int(ctx.menu.page_size)
        for i in 0..<pageSize {
          labels.append(select_labels[i].map { String(cString: $0) } ?? "")
        }
      }
      // swiftlint:enable identifier_name
      let page = Int(ctx.menu.page_no)
      let lastPage = ctx.menu.is_last_page
      visibleCandidates = candidates
      visiblePageSize = Int(ctx.menu.page_size)

      let selRange = NSRange(location: start.utf16Offset(in: preedit), length: preedit.utf16.distance(from: start, to: end))
      showPanel(preedit: inlinePreedit ? "" : preedit, selRange: selRange, caretPos: caretPos.utf16Offset(in: preedit),
                candidates: candidates, comments: comments, labels: labels, highlighted: Int(ctx.menu.highlighted_candidate_index),
                page: page, lastPage: lastPage)
      _ = rimeAPI.free_context(&ctx)
      requestDynamicTranslationIfNeeded()
    } else {
      cancelDynamicTranslation()
      visibleCandidates.removeAll()
      visiblePageSize = 0
      hidePalettes()
    }
  }

  private func requestDynamicTranslationIfNeeded() {
    guard let snapshot = translationSnapshot() else {
      cancelDynamicTranslation()
      return
    }
    let request = candidateTranslation.observe(snapshot)
    guard let request else { updateTranslationPanel(); return }
    sendTranslation(request)
  }

  private func sendTranslation(_ request: RoarkTCandidateTranslationSession.Ticket) {
    let snapshot = request.snapshot
    // Also cancel older work when this candidate has no valid request payload.
    translationClient.cancel(sessionID: translationSessionID, throughGeneration: request.generation - 1)
    translationLoadingTimer?.cancel()
    let loadingTimer = DispatchWorkItem { [weak self] in
      guard let self, self.candidateTranslation.showLoadingIndicator(for: request) else { return }
      self.updateTranslationPanel()
    }
    translationLoadingTimer = loadingTimer
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: loadingTimer)
    updateTranslationPanel()
    guard let candidateRequest = snapshot.translationRequest else {
      candidateTranslation.fail("当前候选不适用于中英翻译", for: request, retryable: false)
      updateTranslationPanel()
      return
    }
    if #unavailable(macOS 26.0) {
      candidateTranslation.fail(.requiresMacOS26, for: request)
      updateTranslationPanel()
      return // Static fallback does not require a dynamic request or language pack.
    }
    // A synchronous cache hit occurs in this same main-queue call after the
    // snapshot above was verified. Async replies must refresh Rime again.
    var replyIsSynchronous = true
    defer { replyIsSynchronous = false }
    translationClient.translate(sessionID: translationSessionID, generation: request.generation,
                                request: candidateRequest) { [weak self] result in
      guard let self, self.candidateTranslation.ticket == request else { return }
      if !replyIsSynchronous {
        guard self.translationSnapshot() == snapshot else { return }
      }
      switch result {
      case let .success(response):
        if !response.translatedText.isEmpty {
          self.candidateTranslation.receive(response.translatedText, for: request, direction: response.direction)
          self.lastTranslationError = nil
        } else {
          self.candidateTranslation.fail("翻译结果与当前候选不匹配", for: request, retryable: false)
        }
      case let .failure(error):
        let failure = CandidateTranslationFailure.from(error)
        self.candidateTranslation.fail(failure, for: request)
        if self.candidateTranslation.commit == nil {
          self.reportTranslationError(failure)
        } else {
          self.lastTranslationError = nil
        }
      }
      // Only redraw the translation action; never recompose or renumber Rime.
      self.updateTranslationPanel()
    }
  }

  private func translationSnapshot() -> RoarkTCandidateSnapshot? {
    translationContext()?.snapshot
  }

  private func translationContext() -> (snapshot: RoarkTCandidateSnapshot, canForget: Bool)? {
    guard session != 0, client != nil, !IsSecureEventInputEnabled(),
          processKey(UInt32(XK_F19), modifiers: 0) else { return nil }
    let values = properties(named: ["roarkt_panel_raw", "roarkt_panel_source", "roarkt_panel_identity",
                                    "roarkt_panel_scope", "roarkt_panel_can_forget"])
    guard let raw = values["roarkt_panel_raw"], !raw.isEmpty,
          let source = values["roarkt_panel_source"], !source.isEmpty,
          let identity = values["roarkt_panel_identity"], !identity.isEmpty,
          let scope = values["roarkt_panel_scope"], ["whole", "segment"].contains(scope) else { return nil }
    return (RoarkTCandidateSnapshot(rawInput: raw, source: source, identity: identity, scope: scope),
            values["roarkt_panel_can_forget"] == "1")
  }

  private func setTranslationProperty(_ name: String, _ value: String) {
    name.withCString { key in value.withCString { rimeAPI.set_property(session, key, $0) } }
  }

  private func updateTranslationPanel() {
    let panel = NSApp.squirrelAppDelegate.panel
    guard panel?.inputController === self else { return }
    panel?.updateTranslation(candidateTranslation)
  }

  func commitTranslationSelection() {
    guard let submission = candidateTranslation.commit,
          translationSnapshot() == submission.snapshot else { return }
    let snapshot = submission.snapshot
    for (key, value) in [("raw", snapshot.rawInput), ("source", snapshot.source),
                         ("identity", snapshot.identity), ("scope", snapshot.scope), ("text", submission.text)] {
      setTranslationProperty("roarkt_panel_commit_" + key, value)
    }
    _ = processKey(UInt32(XK_F20), modifiers: 0)
    guard property(named: "roarkt_panel_committed") == "1" else { return }
    cancelDynamicTranslation()
    rimeUpdate()
  }

  private func cancelDynamicTranslation() {
    translationLoadingTimer?.cancel()
    translationLoadingTimer = nil
    if let request = candidateTranslation.ticket {
      translationClient.cancel(sessionID: translationSessionID, throughGeneration: request.generation)
    }
    candidateTranslation.invalidate()
    updateTranslationPanel()
  }

  private func property(named name: String) -> String? {
    properties(named: [name])[name]
  }

  private func properties(named names: [String]) -> [String: String] {
    propertyReader.read(names) { name, buffer, capacity in
      name.withCString { self.rimeAPI.get_property(self.session, $0, buffer, capacity) }
    }
  }

  private func reportTranslationError(_ error: Error) {
    guard error.localizedDescription != lastTranslationError else { return }
    lastTranslationError = error.localizedDescription
    NSLog("RoarkT dynamic translation failed (code: %ld)", (error as NSError).code)
  }

  func commit(string: String) {
    cancelDynamicTranslation()
    guard let client = client else { return }
    client.insertText(string, replacementRange: .empty)
    preedit = ""
    hidePalettes()
  }

  func show(preedit: String, selRange: NSRange, caretPos: Int) {
    guard let client = client else { return }
    if self.preedit == preedit && self.caretPos == caretPos && self.selRange == selRange {
      return
    }

    self.preedit = preedit
    self.caretPos = caretPos
    self.selRange = selRange

    let start = selRange.location
    let attrString = NSMutableAttributedString(string: preedit)
    if start > 0 {
      let attrs = mark(forStyle: kTSMHiliteConvertedText, at: NSRange(location: 0, length: start))! as! [NSAttributedString.Key: Any]
      attrString.setAttributes(attrs, range: NSRange(location: 0, length: start))
    }
    let remainingRange = NSRange(location: start, length: preedit.utf16.count - start)
    let attrs = mark(forStyle: kTSMHiliteSelectedRawText, at: remainingRange)! as! [NSAttributedString.Key: Any]
    attrString.setAttributes(attrs, range: remainingRange)
    client.setMarkedText(attrString, selectionRange: NSRange(location: caretPos, length: 0), replacementRange: .empty)
  }

  // swiftlint:disable:next function_parameter_count
  func showPanel(preedit: String, selRange: NSRange, caretPos: Int, candidates: [String], comments: [String], labels: [String], highlighted: Int, page: Int, lastPage: Bool) {
    guard let client = client else { return }
    var inputPos = NSRect()
    client.attributes(forCharacterIndex: 0, lineHeightRectangle: &inputPos)
    if let panel = NSApp.squirrelAppDelegate.panel {
      panel.position = inputPos
      panel.inputController = self
      panel.update(preedit: preedit, selRange: selRange, caretPos: caretPos, candidates: candidates, comments: comments, labels: labels,
                   highlighted: highlighted, page: page, lastPage: lastPage, update: true)
    }
  }
}
