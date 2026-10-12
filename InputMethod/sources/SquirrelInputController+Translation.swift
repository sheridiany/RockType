// SPDX-License-Identifier: GPL-3.0-or-later
// Extracted from SquirrelInputController.swift (Leo Liu, 2024).
import Carbon
import InputMethodKit

/// Translation/AI request, cancellation and presentation adapters. Shares the controller lifecycle and generation authority.
extension SquirrelInputController {
  func performTranslationAction() {
    let ai = candidateTranslation.ticket?.action != nil
    guard (ai ? inputPreferences.allowsInputAI : inputPreferences.input.candidateTranslation),
          !IsSecureEventInputEnabled() else { cancelDynamicTranslation(); return }
    if candidateTranslation.canRetry {
      guard translationSnapshot(forAI: candidateTranslation.ticket?.action != nil) == candidateTranslation.ticket?.snapshot,
            let request = candidateTranslation.retry() else { return }
      if request.action != nil { sendInputAI(request) } else { sendTranslation(request) }
    } else {
      commitTranslationSelection()
    }
  }

  func requestDynamicTranslationIfNeeded() {
    if let ticket = candidateTranslation.ticket, ticket.action != nil {
      if inputPreferences.allowsInputAI, translationSnapshot(forAI: true) == ticket.snapshot { updateTranslationPanel(); return }
      cancelDynamicTranslation()
    }
    guard inputPreferences.input.candidateTranslation, let snapshot = translationSnapshot() else {
      cancelDynamicTranslation()
      return
    }
    let request = candidateTranslation.observe(snapshot)
    guard let request else { updateTranslationPanel(); return }
    sendTranslation(request)
  }

  func sendTranslation(_ request: RoarkTCandidateTranslationSession.Ticket) {
    guard inputPreferences.input.candidateTranslation, !IsSecureEventInputEnabled() else { cancelDynamicTranslation(); return }
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
    if RoarkTCandidateSnapshot.preservesTechnicalText(snapshot.source) {
      candidateTranslation.receive(snapshot.source, for: request, direction: candidateRequest.direction.rawValue)
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
    translationClient.translateDebounced(sessionID: translationSessionID, generation: request.generation,
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

  func sendInputAI(_ request: RoarkTCandidateTranslationSession.Ticket) {
    guard let action = request.action, inputPreferences.allowsInputAI,
          translationSnapshot(forAI: true) == request.snapshot else { cancelDynamicTranslation(); return }
    translationLoadingTimer?.cancel()
    inputAIProtection?.invalidate()
    inputAIProtection = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if IsSecureEventInputEnabled() || self.client == nil {
          self.cancelDynamicTranslation()
          self.translationClient.invalidate()
        }
      }
    }
    updateTranslationPanel()
    translationClient.rewrite(sessionID: translationSessionID, generation: request.generation,
      source: request.snapshot.source, action: action, timeout: inputPreferences.input.inputAI?.timeout ?? 30) { [weak self] result in
      guard let self, self.candidateTranslation.ticket == request else { return }
      guard self.inputPreferences.allowsInputAI, self.translationSnapshot(forAI: true) == request.snapshot else { self.cancelDynamicTranslation(); return }
      switch result {
      case let .success(response):
        self.candidateTranslation.receive(response.translatedText, for: request)
      case let .failure(error):
        let failure = RoarkTInputAIAction.failure(error)
        self.candidateTranslation.fail(failure.message, for: request, retryable: failure.retryable)
      }
      self.updateTranslationPanel()
    }
  }

  func updateTranslationPanel() {
    let panel = NSApp.squirrelAppDelegate.panel
    guard panel?.inputController === self else { return }
    panel?.updateTranslation(candidateTranslation)
  }

  func commitTranslationSelection() {
    let ai = candidateTranslation.ticket?.action != nil
    guard (ai ? inputPreferences.allowsInputAI : inputPreferences.input.candidateTranslation),
          let submission = candidateTranslation.commit,
          translationSnapshot(forAI: ai) == submission.snapshot else { return }
    setTranslationProperty("roarkt_panel_commit_ai", ai ? "1" : "")
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

  func cancelDynamicTranslation() {
    inputAIProtection?.invalidate(); inputAIProtection = nil
    translationLoadingTimer?.cancel()
    translationLoadingTimer = nil
    if let request = candidateTranslation.ticket {
      translationClient.cancel(sessionID: translationSessionID, throughGeneration: request.generation)
    }
    candidateTranslation.invalidate()
    updateTranslationPanel()
  }

  func reportTranslationError(_ error: Error) {
    guard error.localizedDescription != lastTranslationError else { return }
    lastTranslationError = error.localizedDescription
    NSLog("RockType dynamic translation failed (code: %ld)", (error as NSError).code)
  }
}
