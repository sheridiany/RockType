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
final class SquirrelInputController: IMKInputController, RoarkTInputMenuActions, @unchecked Sendable {
  // Storage is owned here; internal visibility is only for this type's sibling extensions.
  nonisolated static let keyRollOver = 50

  weak var client: IMKTextInput?
  let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  private var preedit: String = ""
  private var selRange: NSRange = .empty
  private var caretPos: Int = 0
  var lastModifiers: NSEvent.ModifierFlags = .init()
  var session: RimeSessionId = 0
  var schemaId: String = ""
  private var selectedSchema = "roarkt"
  var inputPreferences = InputMethodPreferences.defaults
  private var pendingPreferredSchema: String?

  var hasActiveComposition: Bool {
    guard session != 0, rimeAPI.find_session(session), let input = rimeAPI.get_input(session) else { return false }
    return input.pointee != 0
  }

  func applyPreferences(_ preferences: InputMethodPreferences) {
    if preferences.input.scheme != inputPreferences.input.scheme {
      pendingPreferredSchema = preferences.input.scheme.rawValue
    }
    let translationChanged = preferences.input.candidateTranslation != inputPreferences.input.candidateTranslation
      || preferences.translation != inputPreferences.translation
      || preferences.input.inputAI != inputPreferences.input.inputAI
      || (preferences.inputMethodAIEnabled != inputPreferences.inputMethodAIEnabled
          && candidateTranslation.ticket?.action != nil)
    let modeChanged = preferences.input.showModeIndicator != inputPreferences.input.showModeIndicator
    inputPreferences = preferences
    if translationChanged {
      cancelDynamicTranslation()
      if preferences.input.candidateTranslation, client != nil, session != 0, rimeAPI.find_session(session) {
        requestDynamicTranslationIfNeeded()
      }
    }
    if !preferences.input.showModeIndicator { inputModePanel.hide() }
    else if modeChanged, client != nil { inputModePanel.activate(client: client, ascii: rimeAPI.get_option(session, "ascii_mode")) }
  }

  func applyPendingScheme() {
    guard !hasActiveComposition, let schema = pendingPreferredSchema else { return }
    pendingPreferredSchema = nil
    selectedSchema = schema
    if session != 0, rimeAPI.find_session(session) {
      cancelDynamicTranslation()
      _ = rimeAPI.select_schema(session, schema)
    }
  }

  func prepareForSettingsDeployment() {
    cancelDynamicTranslation()
    inputModePanel.hide()
    destroySession()
  }
  var inlinePreedit = false
  var inlineCandidate = false
  // for chord-typing
  var chordKeyCodes: [UInt32] = .init(repeating: 0, count: SquirrelInputController.keyRollOver)
  var chordModifiers: [UInt32] = .init(repeating: 0, count: SquirrelInputController.keyRollOver)
  var chordKeyCount: Int = 0
  var chordTimer: Timer?
  var chordDuration: TimeInterval = 0
  var currentApp: String = ""
  var visibleCandidates = [String]()
  var visiblePageSize = 0
  let propertyReader = RoarkTRimePropertyReader()
  let translationClient = RoarkTTranslationClient()
  let translationSessionID = UUID().uuidString
  var candidateTranslation = RoarkTCandidateTranslationSession()
  var translationLoadingTimer: DispatchWorkItem?
  var inputAIProtection: Timer?
  var lastTranslationError: String?
  // IMK invokes this controller on the main run loop; assert that boundary.
  lazy var inputModePanel = MainActor.assumeIsolated { RoarkTInputModePanel() }

  var voiceClient: IMKTextInput? {
    guard preedit.isEmpty, !IsSecureEventInputEnabled() else { return nil }
    return client
  }

  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    nonisolated(unsafe) let event = event
    nonisolated(unsafe) let sender = sender
    return MainActor.assumeIsolated {
      handleInputEvent(event, sender: sender)
    }
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
      pendingPreferredSchema = nil // An explicit system input-source selection wins over the pending default.
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
      // Activation has no flagsChanged event; use the session-wide Caps Lock state.
      if CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) {
        lastModifiers.insert(.capsLock)
      } else {
        lastModifiers.remove(.capsLock)
      }
      if let app = client?.bundleIdentifier(), currentApp != app {
        currentApp = app
        updateAppOptions()
      }
      NSApp.squirrelAppDelegate.inputControllerDidActivate(self)
      if inputPreferences.input.showModeIndicator {
        inputModePanel.activate(client: client, ascii: rimeAPI.get_option(session, "ascii_mode"))
      }
    }
  }

  override init!(server: IMKServer!, delegate: Any!, client: Any!) {
    super.init(server: server, delegate: delegate, client: client)
    nonisolated(unsafe) let client = client
    MainActor.assumeIsolated {
      self.client = client as? IMKTextInput
      inputPreferences = RoarkTInputSettings.shared.preferences
      selectedSchema = inputPreferences.input.scheme.rawValue
      RoarkTInputSettings.shared.track(self)
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
      result = makeRoarkTInputMenu(target: self, settingsAvailable:
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ROARKT_APP_BUNDLE_ID) != nil)
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
    // Arguments only reach a newly launched process. An existing main app receives
    // the standard reopen event and routes it to its settings window.
    configuration.appleEvent = NSAppleEventDescriptor(
      eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
      targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID)
    )
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
  }

  isolated deinit {
    translationClient.invalidate()
    destroySession()
  }
}

extension SquirrelInputController {
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
    inputAIProtection?.invalidate(); inputAIProtection = nil
    if session != 0 {
      let sessionID = translationSessionID
      translationClient.cancel(sessionID: sessionID, throughGeneration: candidateTranslation.ticket?.generation ?? 0)
      _ = rimeAPI.destroy_session(session)
      session = 0
    }
    candidateTranslation.invalidate()
    clearChord()
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

  func commit(string: String) {
    cancelDynamicTranslation()
    guard let client = client else { return }
    // Some clients require a marked-text phase even for direct punctuation commits.
    if session != 0, rimeAPI.get_option(session, "force_marked_text_for_direct_commit"),
       preedit.isEmpty, !string.isEmpty {
      let markedText = NSMutableAttributedString(string: string)
      client.setMarkedText(markedText,
                           selectionRange: NSRange(location: markedText.length, length: 0),
                           replacementRange: .empty)
    }
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
