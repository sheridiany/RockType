import AppKit
import Foundation

@main
struct SessionTests {
  static func drainReplies() {
    // FIFO marker follows the production client's queued main-thread reply.
    // Never depend on a fixed 10ms scheduling assumption under concurrent builds.
    var drained = false
    DispatchQueue.main.async { drained = true }
    let deadline = Date().addingTimeInterval(2)
    while !drained && Date() < deadline {
      _ = RunLoop.current.run(mode: .default, before: deadline)
    }
    precondition(drained, "main queue failed to drain")
  }
  static func checkInputAI() {
    let snapshot = RoarkTCandidateSnapshot(rawInput: "yingwenshu", source: "英文书", identity: "7:10:0", scope: "whole")
    var session = RoarkTCandidateTranslationSession()
    let ordinary = session.observe(snapshot)!
    for action in [RoarkTInputAIAction.rewrite, .polish, .translate, .rewrite] {
      let request = session.beginAI(snapshot)
      precondition(request.action == action && request.generation > ordinary.generation)
      precondition(session.isLoading && session.commit == nil && session.interceptsTab)
      precondition(session.displayText == action.title + " · 思考中…")
      precondition(!session.receive("old result", for: ordinary))
      precondition(session.receive("synthetic AI result", for: request))
      precondition(session.commit?.snapshot == snapshot && session.commit?.text == "synthetic AI result")
    }
    let old = session.ticket!
    session.invalidate() // Esc, input change and focus loss revoke the same ticket authority.
    precondition(session.commit == nil && !session.receive("late", for: old))
    let fresh = session.beginAI(snapshot)
    precondition(fresh.action == .rewrite)
    let notConfigured = RoarkTInputAIAction.failure(NSError(domain: CandidateTranslationFailure.errorDomain, code: 101))
    precondition(session.fail(notConfigured.message, for: fresh, retryable: notConfigured.retryable))
    precondition(session.commit == nil && !session.canRetry && session.displayText.contains("未配置 AI"))
    let failure = session.beginAI(snapshot)
    precondition(session.fail("失败", for: failure))
    let retry = session.retry()!
    precondition(retry.action == failure.action && retry.generation > failure.generation)
    let key = Shortcut(key: "tab", modifiers: .option)
    precondition(RoarkTInputAIAction.matches(keyCode: 48, modifiers: .option, shortcut: key))
    precondition(!RoarkTInputAIAction.matches(keyCode: 48, modifiers: [.option, .shift], shortcut: key))
    precondition(!RoarkTInputAIAction.matches(keyCode: 48, modifiers: [], shortcut: key))

    precondition(RoarkTInputAIAction.matches(keyCode: 18, modifiers: [.control, .shift],
      shortcut: Shortcut(key: "1", modifiers: [.control, .shift])))
    let transport = AITransport()
    var secure = false
    let client = RoarkTTranslationClient(proxyProvider: { transport }, isSecureInputEnabled: { secure })
    let id = UUID().uuidString
    var results: [Result<RoarkTTranslationResult, Error>] = []
    func send(_ generation: Int64, timeout: Double = 30) {
      client.rewrite(sessionID: id, generation: generation, source: snapshot.source, action: .rewrite,
                     timeout: timeout) { results.append($0) }
    }
    send(1)
    precondition(transport.ai.count == 1 && results.isEmpty, "explicit request returns without waiting for backend")
    precondition(transport.ai[0].source == snapshot.source && transport.ai[0].action == "rewrite")
    send(2)
    transport.ai[0].reply(1, snapshot.source, "stale", nil)
    drainReplies()
    precondition(results.isEmpty, "superseded AI reply is ignored")
    transport.ai[1].reply(2, "wrong source", "wrong result", nil)
    drainReplies()
    precondition(results.count == 1 && (try? results.last!.get()) == nil)
    send(3)
    transport.ai[2].reply(3, snapshot.source, "synthetic AI result", nil)
    drainReplies()
    precondition((try? results.last!.get().translatedText) == "synthetic AI result")
    client.translate(sessionID: id, generation: 4, request: snapshot.translationRequest!) { _ in }
    precondition(transport.translations == 1, "AI result never enters ordinary translation cache")
    client.cancel(sessionID: id, throughGeneration: 4)
    secure = true
    send(5)
    precondition(transport.ai.count == 3 && (try? results.last!.get()) == nil, "Secure Input sends no AI")
    secure = false
    send(6)
    secure = true
    transport.ai.last!.reply(6, snapshot.source, "protected late reply", nil)
    drainReplies()
    precondition((try? results.last!.get()) == nil, "Secure Input rejects replies in flight")
    secure = false
    send(7)
    client.deactivate()
    let count = results.count
    transport.ai.last!.reply(7, snapshot.source, "late focus reply", nil)
    drainReplies()
    precondition(results.count == count, "deactivation drops late result")
    send(8, timeout: 0.1)
    let deadline = Date().addingTimeInterval(2)
    while results.count == count && Date() < deadline { _ = RunLoop.current.run(mode: .default, before: deadline) }
    precondition(results.count == count + 1 && (try? results.last!.get()) == nil, "bounded AI timeout")
    precondition(transport.cancellations >= 3)
    client.invalidate()
    print("input AI actions, snapshots, stale replies, no cache, secure input, cancellation and timeout passed")

    if ProcessInfo.processInfo.environment["ROARKT_MEASURE_DEBOUNCE"] == "1" {
      var samples: [Double] = []
      for _ in 0..<20 {
        let proxy = AITransport()
        let measured = RoarkTTranslationClient(proxyProvider: { proxy }, isSecureInputEnabled: { false })
        let start = ProcessInfo.processInfo.systemUptime
        measured.translateDebounced(sessionID: UUID().uuidString, generation: 1, request: snapshot.translationRequest!) { _ in }
        let deadline = Date().addingTimeInterval(2)
        while proxy.translations == 0 && Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001)) }
        precondition(proxy.translations == 1)
        samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        measured.invalidate()
      }
      samples.sort()
      print("candidate-client-ms n=20 median=\(samples[10]) p95=\(samples[18])")
    }
  }

  static func checkFocusAndReentry() {
    let source = RoarkTCandidateSnapshot(rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
    let transport = AITransport()
    let client = RoarkTTranslationClient(proxyProvider: { transport }, isSecureInputEnabled: { false })
    var state = RoarkTCandidateTranslationSession()
    let id = UUID().uuidString
    var delivered: [String] = []
    func request(_ ticket: RoarkTCandidateTranslationSession.Ticket) {
      client.rewrite(sessionID: id, generation: ticket.generation, source: source.source, action: ticket.action!, timeout: 30) {
        if case let .success(value) = $0, state.receive(value.translatedText, for: ticket) { delivered.append(value.translatedText) }
      }
    }
    client.activate()
    let first = state.beginAI(source)
    request(first)
    // A reply already queued on main when focus is lost must not revive the old ticket.
    transport.ai[0].reply(first.generation, source.source, "obsolete queued result", nil)
    state.invalidate()
    client.deactivate()
    client.activate()
    let second = state.beginAI(source)
    precondition(second.generation > first.generation)
    request(second)
    drainReplies()
    precondition(delivered.isEmpty && state.commit == nil, "same-source reentry cannot accept old replies")
    transport.ai[1].reply(second.generation, source.source, "current result", nil)
    drainReplies()
    precondition(delivered == ["current result"] && state.commit?.text == "current result")
    let cancelled = state.beginAI(source)
    request(cancelled)
    client.cancel(sessionID: id, throughGeneration: cancelled.generation)
    state.invalidate()
    transport.ai[2].reply(cancelled.generation, source.source, "cancelled result", nil)
    drainReplies()
    precondition(delivered == ["current result"] && state.commit == nil)
    // Returning from AI to ordinary translation cannot let an old AI failure replace the new result.
    let normal = state.observe(source)!
    precondition(state.receive("hello", for: normal))
    precondition(!state.fail("late AI failure", for: cancelled) && state.commit?.text == "hello")
    client.invalidate()
    print("Focus/reentry, queued AI success, cancellation and stale failure regression passed")
  }

  static func main() {
    checkInputAI()
    checkFocusAndReentry()
    for identifier in [ROARKT_APP_BUNDLE_ID, ROARKT_TRANSLATION_SERVICE_NAME, Identifiers.inputMethodBundleID] {
      let previous = "anchor apple generic and certificate leaf[subject.OU] = \"\(ROARKT_TEAM_ID)\" and identifier \"\(identifier)\""
      precondition(Identifiers.codeRequirement(for: identifier) == previous,
                   "centralizing XPC requirements must preserve the exact signing identity")
    }

    var session = RoarkTCandidateTranslationSession()
    let first = RoarkTCandidateSnapshot(
      rawInput: "lixian", source: "李先", identity: "0:6:0", scope: "whole")
    let second = RoarkTCandidateSnapshot(
      rawInput: "lixian", source: "离线", identity: "0:6:1", scope: "whole")
    let old = session.observe(first)!
    let current = session.observe(second)!
    precondition(
      !session.receive("Mr. Li", for: old), "old selection must not overwrite new selection")
    precondition(session.commit == nil, "loading must not submit stale translation")
    precondition(session.receive("Offline", for: current))
    precondition(session.commit?.text == "Offline")
    precondition(session.commit?.snapshot == second, "Tab can directly submit the current result")
    precondition(
      session.observe(second) == nil, "reading the result must not request a reverse translation")
    session.invalidate()
    precondition(session.commit == nil)
    precondition(!session.receive("Late result", for: current))
    let failed = session.observe(second)!
    precondition(session.fail("temporary failure", for: failed))
    precondition(session.observe(second) == nil, "redraw must not automatically retry")
    guard let retried = session.retry() else {
      fatalError("the user can retry the same failed candidate")
    }
    precondition(retried.generation > failed.generation)
    precondition(session.retry() == nil, "only one attempt may be in flight")
    precondition(session.commit == nil)
    precondition(!session.receive("Old attempt", for: failed))
    precondition(session.receive("Offline", for: retried))
    precondition(
      !session.fail("late failure", for: retried), "a second terminal reply must be ignored")
    precondition(session.commit?.text == "Offline")
    precondition(session.retry() == nil, "a ready result should commit, not retry")
    session.invalidate()
    precondition(session.retry() == nil)
    let permanent = session.observe(second)!
    precondition(session.fail("prepare language pack", for: permanent, retryable: false))
    precondition(!session.canRetry && session.retry() == nil)
    precondition(!session.receive("late success", for: permanent))
    for failure in [
      CandidateTranslationFailure.languagePackMissing, .requiresMacOS26, .incompatibleVersion,
      .invalidResponse, .unauthorized, .cancelled, .unsupportedLanguage,
    ] {
      let wireError = failure as NSError
      precondition(CandidateTranslationFailure.from(wireError) == failure)
      precondition(!failure.canRetry)
    }
    precondition(CandidateTranslationFailure.timedOut.canRetry)
    precondition(CandidateTranslationFailure.serviceUnavailable.canRetry)
    precondition(CandidateTranslationFailure.from(CancellationError()) == .cancelled)
    let greeting = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
    let unsupported = session.observe(greeting)!
    precondition(session.fail(.requiresMacOS26, for: unsupported))
    precondition(
      session.commit?.text == "hello", "unsupported system can submit a matching static translation"
    )
    precondition(session.commit?.snapshot == greeting)
    precondition(!session.isLoading && !session.canRetry)
    let accented = RoarkTCandidateSnapshot(
      rawInput: "cafe", source: "café", identity: "0:4:0", scope: "whole")
    let candidateRequest = accented.translationRequest!
    precondition(candidateRequest.direction == .englishToChinese)
    precondition(candidateRequest.accepts(source: "café", direction: "en-zh"))
    precondition(
      !candidateRequest.accepts(source: "café", direction: "zh-en"),
      "wrong direction cannot be committed")
    precondition(
      !candidateRequest.accepts(source: "cafe", direction: "en-zh"),
      "input code cannot replace source")
    precondition(second.translationRequest?.direction == .chineseToEnglish)
    verifyInactiveCacheExpiry()
    verifyCacheAcrossFocusChanges()
    verifyConnectionLifetime()
    verifyPropertyReaderAndPage()
    verifyTabDecision()
    verifySecureCacheBoundary()
    verifyDebounceAndTechnicalProtection()
    verifyClientReuse()
    verifyCache()
    verifyCompositionBoundaries()
    verifyLoadingPresentation()
    verifyStaticFallback()
    print(
      "candidate selection, submission, loading grace period, Tab policy, LRU/cache transport, property reuse, page size, active connection lifetime, focus cache/expiry, composition boundaries, static fallback and cancellation passed"
    )
  }

  static func verifyInactiveCacheExpiry() {
    var cache = RoarkTTranslationCache()
    let request = try! CandidateTranslationRequest(
      rawInput: "nihao", sourceText: "你好", identity: "0:5:0", scope: .whole)
    cache.insert("hello", for: request, now: 0)
    precondition(cache.nextExpiration == 300)
    cache.removeExpired(at: 299)
    precondition(cache.nextExpiration == 300)
    cache.removeExpired(at: 300)
    precondition(cache.nextExpiration == nil, "expire stored text even if no later lookup occurs")
  }

  static func verifyCacheAcrossFocusChanges() {
    var now: TimeInterval = 0
    var secure = false
    let transport = TranslationTransport()
    let client = RoarkTTranslationClient(
      proxyProvider: { transport }, isSecureInputEnabled: { secure }, now: { now })
    let request = try! CandidateTranslationRequest(
      rawInput: "nihao", sourceText: "你好", identity: "0:5:0", scope: .whole)
    var generations: [Int64] = []
    func translate(_ generation: Int64) {
      client.translate(sessionID: "focus", generation: generation, request: request) { result in
        if case .success(let response) = result { generations.append(response.generation) }
      }
    }
    client.activate()
    translate(1)
    transport.respond(text: "hello")
    drainReplies()
    client.deactivate()
    now = 32
    client.activate()
    translate(2)
    precondition(
      transport.requests == 1 && generations == [1, 2],
      "focus switch preserves results, never old commit generation")
    client.deactivate()
    now = 300
    client.activate()
    translate(3)
    precondition(
      transport.requests == 2, "focus changes and cache hits do not extend the five-minute lifetime"
    )
    client.deactivate()
    transport.respond(text: "cancelled")
    drainReplies()
    precondition(generations == [1, 2], "deactivation cancels pending replies")
    client.activate()
    translate(4)
    transport.respond(text: "hello")
    drainReplies()
    client.deactivate()
    secure = true
    client.activate()
    secure = false
    translate(5)
    precondition(
      transport.requests == 4, "secure activation clears results from earlier applications")
    client.deactivate()
    client.invalidate()
  }

  static func verifyConnectionLifetime() {
    var policy = RoarkTTranslationConnectionPolicy()
    precondition(policy.disconnectDelay(at: 0, hasPendingRequests: false) == 0)
    policy.activate(at: 10)
    precondition(
      policy.disconnectDelay(at: 42, hasPendingRequests: false) == 568,
      "daily 32-second pauses must keep the worker warm")
    precondition(policy.disconnectDelay(at: 609, hasPendingRequests: false) == 1)
    precondition(
      policy.disconnectDelay(at: 610, hasPendingRequests: false) == 0,
      "ten minutes without input permits release")
    policy.recordActivity(at: 609)
    precondition(
      policy.disconnectDelay(at: 610, hasPendingRequests: false) == 599,
      "ordinary keys reset the deadline without sending XPC")
    precondition(
      policy.disconnectDelay(at: 1300, hasPendingRequests: true) == nil,
      "an in-flight translation must never be disconnected by the idle timer")
    policy.deactivate()
    precondition(
      policy.disconnectDelay(at: 610, hasPendingRequests: false) == 0,
      "leaving the input method releases the connection immediately")
    policy.activate(at: 620)
    precondition(policy.disconnectDelay(at: 652, hasPendingRequests: false) == 568)
  }

  static func verifyPropertyReaderAndPage() {
    let reader = RoarkTRimePropertyReader(capacity: 8)
    var addresses = Set<UInt>()
    func fetch(_ name: String, _ buffer: UnsafeMutablePointer<CChar>, _ capacity: Int) -> Bool {
      addresses.insert(UInt(bitPattern: buffer))
      if name == "missing" { return false }
      if name == "overflow" {
        buffer.update(repeating: 65, count: capacity)
        return true
      }
      let text = name == "long" ? "abcdef" : "ok"
      text.withCString { buffer.update(from: $0, count: text.utf8.count + 1) }
      return true
    }
    let properties = reader.read(["long", "short", "missing", "overflow"], fetch: fetch)
    precondition(properties["long"] == "abcdef" && properties["short"] == "ok")
    precondition(properties["missing"] == nil && properties["overflow"] == nil)
    precondition(reader.read(["short"], fetch: fetch)["short"] == "ok")
    precondition(addresses.count == 1, "reuse one property buffer across properties and updates")
    let snapshot = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你好", identity: "0:5:8", scope: "whole")
    precondition(snapshot.isSelected(index: 2, pageSize: 3))
    precondition(!snapshot.isSelected(index: 2, pageSize: 5))
    precondition(!snapshot.isSelected(index: 0, pageSize: 0))
  }

  static func verifyTabDecision() {
    var session = RoarkTCandidateTranslationSession()
    let snapshot = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
    precondition(!session.interceptsTab)
    let first = session.observe(snapshot)!
    precondition(
      session.interceptsTab && session.commit == nil,
      "loading without any text still protects focus/composition")
    session.receive("hello", for: first)
    precondition(session.interceptsTab)
    session.invalidate()
    let failed = session.observe(snapshot)!
    session.fail("transient", for: failed)
    precondition(session.interceptsTab && session.canRetry)
    let retry = session.retry()!
    session.fail(.invalidRequest, for: retry)
    precondition(!session.interceptsTab, "permanent failure returns Tab to Rime")
    session.invalidate()
    precondition(!session.interceptsTab)
  }

  static func verifySecureCacheBoundary() {
    var secure = false
    let transport = TranslationTransport()
    let client = RoarkTTranslationClient(
      proxyProvider: { transport }, isSecureInputEnabled: { secure })
    let request = try! CandidateTranslationRequest(
      rawInput: "nihao", sourceText: "你好", identity: "0:5:0", scope: .whole)
    var successes = 0
    func translate(_ generation: Int64) {
      client.translate(sessionID: "secure-test", generation: generation, request: request) {
        result in
        if case .success = result { successes += 1 }
      }
    }
    translate(1)
    secure = true
    transport.respond(text: "hello")
    drainReplies()
    precondition(successes == 0, "secure input rejects late results before caching")
    translate(2)
    precondition(transport.requests == 1, "secure input never sends source text")
    secure = false
    translate(3)
    precondition(transport.requests == 2, "secure late result was not cached")
    transport.respond(text: "hello")
    drainReplies()
    secure = true
    translate(4)
    secure = false
    translate(5)
    precondition(transport.requests == 3, "entering secure input clears reusable text")
    client.invalidate()
  }

  static func verifyDebounceAndTechnicalProtection() {
    let transport = TranslationTransport()
    var secure = false
    let client = RoarkTTranslationClient(proxyProvider: { transport }, isSecureInputEnabled: { secure })
    let phrase = try! CandidateTranslationRequest(rawInput: "hello'world", sourceText: "hello world", identity: "0:11:0", scope: .whole)
    var received: [Int64] = []
    func send(_ generation: Int64) {
      client.translateDebounced(sessionID: "debounce", generation: generation, request: phrase, delay: 0.01) {
        if case .success(let result) = $0 { received.append(result.generation) }
      }
    }
    send(1); send(2); send(3)
    precondition(transport.requests == 0, "keystrokes return before uncached XPC")
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    precondition(transport.requests == 1, "only the settled phrase reaches XPC")
    transport.respond(text: "你好世界"); drainReplies()
    precondition(received == [3], "superseded generations cannot reply")
    send(4)
    precondition(received == [3, 4] && transport.requests == 1, "phrase cache hits bypass debounce")
    client.invalidate()
    send(5); client.cancel(sessionID: "debounce", throughGeneration: 5)
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    precondition(transport.requests == 1, "cancel removes queued dispatch")
    send(6); secure = true
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    precondition(transport.requests == 1 && received == [3, 4], "security is rechecked after debounce")
    secure = false
    for text in ["SwiftUI", "OpenAI", "URLSession", "loadUser", "user_id", "main.swift", "fetch()", "API", "C++", "C#", "安装Docker", "使用API调用", "修复 loadUser 的问题"] {
      precondition(RoarkTCandidateSnapshot.preservesTechnicalText(text))
      let request = try! CandidateTranslationRequest(rawInput: "test", sourceText: text, identity: "0:4:0", scope: .whole)
      var preserved: String?
      client.translateDebounced(sessionID: "code", generation: 1, request: request) {
        if case .success(let result) = $0 { preserved = result.translatedText }
      }
      precondition(preserved == text && transport.requests == 1, "technical text stays local and exact")
    }
    for text in ["Hello", "hello world", "你好", "今天下午开会"] {
      precondition(!RoarkTCandidateSnapshot.preservesTechnicalText(text), "ordinary prose still translates")
    }
    client.invalidate()
  }

  static func verifyClientReuse() {
    let transport = TranslationTransport()
    let client = RoarkTTranslationClient(
      proxyProvider: { transport }, isSecureInputEnabled: { false })
    let snapshot = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
    let other = RoarkTCandidateSnapshot(
      rawInput: "shijie", source: "世界", identity: "0:6:0", scope: "whole")
    var session = RoarkTCandidateTranslationSession()
    func request(_ snapshot: RoarkTCandidateSnapshot) {
      let ticket = session.observe(snapshot)!
      client.translate(
        sessionID: "test", generation: ticket.generation, request: snapshot.translationRequest!
      ) { result in
        if case .success(let response) = result {
          precondition(response.generation == ticket.generation)
          session.receive(response.translatedText, for: ticket, direction: response.direction)
        }
      }
    }
    request(snapshot)
    transport.respond(text: "hello")
    drainReplies()
    precondition(session.commit?.text == "hello")
    request(other)
    transport.respond(text: "world")
    drainReplies()
    request(snapshot)
    precondition(
      transport.requests == 2 && transport.cancellations == 0,
      "returning to a candidate sends no XPC")
    precondition(session.commit?.snapshot == snapshot && session.commit?.text == "hello")
    client.invalidate()
    session.invalidate()
    request(snapshot)
    transport.respond(text: nil, error: CandidateTranslationFailure.timedOut)
    drainReplies()
    session.invalidate()
    request(snapshot)
    precondition(transport.requests == 4, "failure must not populate cache")
    client.cancel(sessionID: "test", throughGeneration: session.ticket!.generation)
    transport.respond(text: "cancelled success")
    drainReplies()
    session.invalidate()
    request(snapshot)
    precondition(transport.requests == 5, "cancelled late success must not populate cache")
    transport.respond(text: "")
    drainReplies()
    session.invalidate()
    request(snapshot)
    precondition(transport.requests == 6, "empty results must not populate cache")
    client.invalidate()
  }

  static func verifyCache() {
    let first = try! CandidateTranslationRequest(
      rawInput: "nihao", sourceText: "你好", identity: "0:5:0", scope: .whole)
    let returned = try! CandidateTranslationRequest(
      rawInput: "nh", sourceText: "你好", identity: "0:2:3", scope: .whole)
    let segment = try! CandidateTranslationRequest(
      rawInput: "nh", sourceText: "你好", identity: "0:2:3", scope: .segment)
    let other = try! CandidateTranslationRequest(
      rawInput: "shijie", sourceText: "世界", identity: "0:6:0", scope: .whole)
    var cache = RoarkTTranslationCache(maximumEntries: 2, maximumBytes: 100, lifetime: 10)
    cache.insert("hello", for: first, now: 0)
    precondition(
      cache.text(for: returned, now: 1) == "hello",
      "input code/selection identity do not affect backend semantics")
    precondition(cache.text(for: segment, now: 1) == nil, "scope semantics stay separate")
    cache.insert("world", for: other, now: 1)
    _ = cache.text(for: first, now: 2)
    cache.insert("segment", for: segment, now: 2)
    precondition(cache.text(for: other, now: 3) == nil, "evict least recently used entry")
    precondition(cache.text(for: first, now: 3) == "hello")
    precondition(cache.text(for: first, now: 10) == nil, "hits do not extend plaintext lifetime")
    cache.insert("", for: other, now: 3)
    precondition(cache.text(for: other, now: 3) == nil)
    var bounded = RoarkTTranslationCache(maximumEntries: 10, maximumBytes: 50, lifetime: 10)
    bounded.insert("hello", for: first, now: 0)
    bounded.insert("world", for: other, now: 0)
    precondition(bounded.text(for: first, now: 1) == nil, "UTF-8 key and value bytes are bounded")
    precondition(bounded.text(for: other, now: 1) == "world")
    bounded.insert(String(repeating: "字", count: 20), for: segment, now: 1)
    precondition(bounded.text(for: segment, now: 1) == nil, "oversized result is not retained")
    bounded.removeAll()
    precondition(bounded.text(for: other, now: 1) == nil)
  }

  static func verifyCompositionBoundaries() {
    let first = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
    let continuous = RoarkTCandidateSnapshot(
      rawInput: "nihaoa", source: "你好啊", identity: "0:6:0", scope: "whole")
    for boundary in ["commit", "Escape/empty composition", "focus loss/activation"] {
      var session = RoarkTCandidateTranslationSession()
      let ready = session.observe(first)!
      session.receive("hello", for: ready)
      let old = session.observe(continuous)!
      precondition(
        session.displayText == "hello" && session.commit == nil,
        "continuous typing retains only disabled text")
      // These controller boundaries all invalidate presentation authority.
      session.invalidate()
      let next = session.observe(first)!
      precondition(
        session.displayText.isEmpty && session.commit == nil,
        "\(boundary): new composition must not display the previous translation, even for identical input"
      )
      precondition(next.generation > old.generation)
      precondition(!session.receive("late result", for: old))
      precondition(!session.showLoadingIndicator(for: old))
      precondition(session.displayText.isEmpty)
    }
  }

  static func verifyLoadingPresentation() {
    var session = RoarkTCandidateTranslationSession()
    let first = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
    let second = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你号", identity: "0:5:1", scope: "whole")
    let old = session.observe(first)!
    precondition(session.displayText.isEmpty, "initial loading waits before showing an indicator")
    precondition(session.receive("hello", for: old))
    let current = session.observe(second)!
    precondition(session.displayText == "hello", "keep the previous result during the grace period")
    precondition(session.commit == nil, "the displayed old result is never submittable")
    precondition(
      !session.showLoadingIndicator(for: old), "old timers cannot alter current presentation")
    precondition(session.showLoadingIndicator(for: current))
    precondition(session.displayText == "正在翻译…")
    precondition(session.receive("new result", for: current))
    precondition(!session.showLoadingIndicator(for: current), "a fast success wins over the timer")
    precondition(session.displayText == "new result")
    session.invalidate()
    precondition(session.displayText.isEmpty, "focus/composition cancellation clears retained text")
  }

  static func verifyStaticFallback() {
    let known = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
    for failure in [
      CandidateTranslationFailure.requiresMacOS26, .languagePackMissing, .serviceUnavailable,
      .timedOut,
    ] {
      var session = RoarkTCandidateTranslationSession()
      let request = session.observe(known)!
      precondition(session.fail(failure, for: request))
      precondition(session.commit?.text == "hello")
      precondition(!session.receive("Late dynamic result", for: request))
      session.invalidate()
      precondition(session.commit == nil)
    }
    for failure in [
      CandidateTranslationFailure.cancelled, .unauthorized, .incompatibleVersion,
      .invalidResponse, .invalidRequest, .unsupportedLanguage,
    ] {
      var session = RoarkTCandidateTranslationSession()
      let request = session.observe(known)!
      precondition(session.fail(failure, for: request))
      precondition(
        session.commit == nil, "static fallback must not mask security/protocol failures")
    }
    var session = RoarkTCandidateTranslationSession()
    let old = session.observe(known)!
    let unknown = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你号", identity: "0:5:1", scope: "whole")
    let current = session.observe(unknown)!
    precondition(
      !session.fail(.timedOut, for: old),
      "an old failure cannot restore the previous word's fallback")
    precondition(session.fail(.timedOut, for: current))
    precondition(
      session.commit == nil && session.canRetry, "same pinyin must not imply same translation")

    let partial = RoarkTCandidateSnapshot(
      rawInput: "nihaoshijie", source: "你好", identity: "0:5:0", scope: "segment")
    let partialRequest = session.observe(partial)!
    precondition(session.fail(.languagePackMissing, for: partialRequest))
    precondition(session.commit?.text == "hello" && session.commit?.snapshot == partial)
    let whole = RoarkTCandidateSnapshot(
      rawInput: "nihaoshijie", source: "你好世界", identity: "0:11:0", scope: "whole")
    let wholeRequest = session.observe(whole)!
    precondition(session.fail(.requiresMacOS26, for: wholeRequest))
    precondition(
      session.commit == nil && !session.canRetry,
      "do not stitch words into an invented sentence translation")
    precondition(session.failure?.contains("无匹配的静态译文") == true)

    let pairs = [
      ("你好", "hello"), ("谢谢", "thanks"), ("早上好", "good morning"),
      ("晚安", "good night"), ("再见", "goodbye"), ("世界", "world"),
      ("输入法", "input method"), ("中文", "Chinese"), ("英文", "English"), ("测试", "test"),
    ]
    for (chinese, english) in pairs {
      for (source, expected) in [(chinese, english), (english.uppercased(), chinese)] {
        let snapshot = RoarkTCandidateSnapshot(
          rawInput: "x", source: source, identity: "0:1:0", scope: "whole")
        let request = session.observe(snapshot)!
        precondition(session.fail(.requiresMacOS26, for: request))
        precondition(session.commit?.text == expected)
      }
    }
    let flypy = RoarkTCandidateSnapshot(
      rawInput: "nihc", source: "你好", identity: "0:4:0", scope: "whole")
    let flypyRequest = session.observe(flypy)!
    precondition(session.fail(.requiresMacOS26, for: flypyRequest))
    precondition(session.commit?.text == "hello", "fallback is independent of the input scheme")
  }
}

private final class TranslationTransport: NSObject, RoarkTTranslationXPCProtocol {
  var requests = 0
  var cancellations = 0
  private var reply: ((Int64, String?, String?, String?, Error?) -> Void)?
  private var generation: Int64 = 0
  private var request: [String: String] = [:]
  func translateCandidate(
    sessionID: String, generation: Int64, request: [String: String],
    withReply reply: @escaping (Int64, String?, String?, String?, Error?) -> Void
  ) {
    requests += 1
    self.generation = generation
    self.request = request
    self.reply = reply
  }
  func respond(text: String?, error: Error? = nil) {
    reply?(generation, request["direction"], request["sourceText"], text, error)
    reply = nil
  }
  func cancel(sessionID: String, throughGeneration: Int64) { cancellations += 1 }
  func registerDictationEndpoint(_ endpoint: NSXPCListenerEndpoint) {}
  func dictationEndpoint(reply: @escaping (NSXPCListenerEndpoint?) -> Void) { reply(nil) }
  func ping(reply: @escaping (String) -> Void) { reply("test") }
  func recordControllerInput() {}
  func controllerInputGeneration(reply: @escaping (Int64, Error?) -> Void) { reply(0, nil) }
}

private final class AITransport: NSObject, RoarkTInputAIXPCProtocol {
  struct Call {
    let source: String
    let action: String
    let reply: (Int64, String?, String?, Error?) -> Void
  }
  var ai: [Call] = []
  var translations = 0
  var cancellations = 0
  func rewriteCandidate(sessionID: String, generation: Int64, text: String, action: String,
                        withReply reply: @escaping (Int64, String?, String?, Error?) -> Void) {
    ai.append(Call(source: text, action: action, reply: reply))
  }
  func configureAI(config: [String: String], withReply reply: @escaping (Error?) -> Void) { reply(nil) }
  func translateText(sessionID: String, generation: Int64, text: String, target: String,
                     withReply reply: @escaping (Int64, String?, Error?) -> Void) { reply(generation, text, nil) }
  func cancelText(sessionID: String, throughGeneration: Int64) {}
  func translateCandidate(sessionID: String, generation: Int64, request: [String: String],
                          withReply reply: @escaping (Int64, String?, String?, String?, Error?) -> Void) { translations += 1 }
  func cancel(sessionID: String, throughGeneration: Int64) { cancellations += 1 }
  func registerDictationEndpoint(_ endpoint: NSXPCListenerEndpoint) {}
  func dictationEndpoint(reply: @escaping (NSXPCListenerEndpoint?) -> Void) { reply(nil) }
  func ping(reply: @escaping (String) -> Void) { reply("test") }
  func recordControllerInput() {}
  func controllerInputGeneration(reply: @escaping (Int64, Error?) -> Void) { reply(0, nil) }
}
