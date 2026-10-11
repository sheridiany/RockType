import Carbon
import Foundation

struct RoarkTTranslationResult {
  let generation: Int64
  let direction: String
  let sourceText: String
  let translatedText: String
}

// Memory only. Exact source, direction, scope and protocol/backend semantics;
// raw input and candidate identity are freshness checks, not translation context.
struct RoarkTTranslationCache {
  private struct CacheKey: Hashable {
    let source: String
    let direction: String
    let scope: String
    let semantics = "apple-translation-v" + CandidateTranslationRequest.version

    init(_ request: CandidateTranslationRequest) {
      source = request.sourceText
      direction = request.direction.rawValue
      scope = request.scope.rawValue
    }
    var bytes: Int { source.utf8.count + direction.utf8.count + scope.utf8.count + semantics.utf8.count }
  }
  private struct Entry {
    let text: String
    let expires: TimeInterval
    let bytes: Int
  }
  private let maximumEntries: Int
  private let maximumBytes: Int
  private let lifetime: TimeInterval
  private var entries: [CacheKey: Entry] = [:]
  private var recency: [CacheKey] = [] // oldest first; bounded at 128 by default
  private var bytes = 0

  init(maximumEntries: Int = 128, maximumBytes: Int = 262_144, lifetime: TimeInterval = 300) {
    self.maximumEntries = max(0, maximumEntries)
    self.maximumBytes = max(0, maximumBytes)
    self.lifetime = max(0, lifetime)
  }

  mutating func text(for request: CandidateTranslationRequest, now: TimeInterval) -> String? {
    removeExpired(at: now)
    let key = CacheKey(request)
    guard let entry = entries[key] else { return nil }
    recency.removeAll { $0 == key }
    recency.append(key)
    return entry.text
  }

  mutating func insert(_ text: String, for request: CandidateTranslationRequest, now: TimeInterval) {
    removeExpired(at: now)
    let key = CacheKey(request)
    let size = key.bytes + text.utf8.count
    guard !text.isEmpty, maximumEntries > 0, size <= maximumBytes, lifetime > 0 else { return }
    remove(key)
    entries[key] = Entry(text: text, expires: now + lifetime, bytes: size)
    recency.append(key)
    bytes += size
    while entries.count > maximumEntries || bytes > maximumBytes {
      remove(recency[0])
    }
  }

  mutating func removeAll() {
    entries.removeAll()
    recency.removeAll()
    bytes = 0
  }

  var nextExpiration: TimeInterval? { entries.values.map(\.expires).min() }

  mutating func removeExpired(at now: TimeInterval) {
    for key in recency.filter({ entries[$0]!.expires <= now }) { remove(key) }
  }

  private mutating func remove(_ key: CacheKey) {
    if let entry = entries.removeValue(forKey: key) { bytes -= entry.bytes }
    recency.removeAll { $0 == key }
  }
}

// Pure lifecycle policy. No connection is created merely by activating or typing.
struct RoarkTTranslationConnectionPolicy {
  private var isActive = false
  private var lastActivity: TimeInterval = 0

  mutating func activate(at now: TimeInterval) {
    isActive = true
    lastActivity = now
  }

  mutating func recordActivity(at now: TimeInterval) {
    lastActivity = now
  }

  mutating func deactivate() { isActive = false }

  func disconnectDelay(at now: TimeInterval, hasPendingRequests: Bool) -> TimeInterval? {
    guard !hasPendingRequests else { return nil }
    return isActive ? max(0, 600 - (now - lastActivity)) : 0
  }
}

final class RoarkTTranslationClient: @unchecked Sendable {
  private final class WeakReference: @unchecked Sendable {
    weak var value: RoarkTTranslationClient?

    init(_ value: RoarkTTranslationClient) {
      self.value = value
    }
  }

  typealias Completion = (Result<RoarkTTranslationResult, Error>) -> Void

  private struct Pending {
    let generation: Int64
    let completion: Completion
    let request: CandidateTranslationRequest
    let timeout: DispatchWorkItem
  }

  private let now: () -> TimeInterval
  private let isSecureInputEnabled: () -> Bool
  private let proxyProvider: (() -> RoarkTTranslationXPCProtocol?)?

  init(proxyProvider: (() -> RoarkTTranslationXPCProtocol?)? = nil,
       isSecureInputEnabled: @escaping () -> Bool = { IsSecureEventInputEnabled() },
       now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
    self.proxyProvider = proxyProvider
    self.isSecureInputEnabled = isSecureInputEnabled
    self.now = now
  }

  private var cache = RoarkTTranslationCache()
  private var connectionPolicy = RoarkTTranslationConnectionPolicy()
  private var cacheExpiry: DispatchWorkItem?
  private var idleDisconnect: DispatchWorkItem?
  private var connection: NSXPCConnection?
  private var connectionToken = UUID()
  private var nextControllerReport: TimeInterval = 0
  private var pending: [String: Pending] = [:]

  func activate() {
    assertMainQueue()
    if isSecureInputEnabled() { clearCache() }
    connectionPolicy.activate(at: now())
    scheduleIdleDisconnect()
  }

  func noteInputActivity() {
    assertMainQueue()
    if isSecureInputEnabled() { clearCache() }
    connectionPolicy.recordActivity(at: now())
    scheduleIdleDisconnect()
  }

  func translate(
    sessionID: String,
    generation: Int64,
    request: CandidateTranslationRequest,
    completion: @escaping Completion
  ) {
    assertMainQueue()
    defer { scheduleIdleDisconnect(); scheduleCacheExpiry() }
    cancel(sessionID: sessionID, throughGeneration: generation - 1)
    guard !isSecureInputEnabled() else {
      clearCache()
      completion(.failure(CandidateTranslationFailure.cancelled))
      return
    }

    if let text = cache.text(for: request, now: now()) {
      completion(.success(.init(generation: generation, direction: request.direction.rawValue,
                               sourceText: request.sourceText, translatedText: text)))
      return
    }

    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.pending[sessionID]?.generation == generation else { return }
      self.pending[sessionID] = nil
      self.cancellationProxy()?.cancel(sessionID: sessionID, throughGeneration: generation)
      self.scheduleIdleDisconnect()
      completion(.failure(CandidateTranslationFailure.timedOut))
    }
    pending[sessionID] = Pending(generation: generation, completion: completion, request: request, timeout: timeout)
    DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)

    guard let proxy = proxy(errorHandler: { [weak self] error in
      DispatchQueue.main.async { self?.finish(sessionID: sessionID, generation: generation, result: .failure(error)) }
    }) else {
      finish(sessionID: sessionID, generation: generation, result: .failure(CandidateTranslationFailure.serviceUnavailable))
      return
    }

    let weakClient = WeakReference(self)
    proxy.translateCandidate(
      sessionID: sessionID,
      generation: generation,
      request: request.payload
    ) { returnedGeneration, direction, returnedSource, translatedText, error in
      DispatchQueue.main.async {
        guard let self = weakClient.value else { return }
        if let error {
          self.finish(sessionID: sessionID, generation: generation, result: .failure(error))
          return
        }
        guard returnedGeneration == generation,
              let direction, let returnedSource, let translatedText,
              request.accepts(source: returnedSource, direction: direction) else {
          self.finish(
            sessionID: sessionID,
            generation: generation,
            result: .failure(CandidateTranslationFailure.invalidResponse)
          )
          return
        }
        self.finish(
          sessionID: sessionID,
          generation: returnedGeneration,
          result: .success(.init(
            generation: returnedGeneration,
            direction: direction,
            sourceText: returnedSource,
            translatedText: translatedText
          ))
        )
      }
    }
  }

  func recordControllerInput() {
    assertMainQueue()
    guard !isSecureInputEnabled(), now() >= nextControllerReport else { return }
    nextControllerReport = now() + 1
    proxy()?.recordControllerInput()
    scheduleIdleDisconnect()
  }

  func cancel(sessionID: String, throughGeneration: Int64) {
    assertMainQueue()
    defer { scheduleIdleDisconnect() }
    guard let request = pending[sessionID], request.generation <= throughGeneration else { return }
    request.timeout.cancel()
    pending[sessionID] = nil
    cancellationProxy()?.cancel(sessionID: sessionID, throughGeneration: throughGeneration)
  }

  // Drop presentation/request authority on focus loss, but keep bounded text
  // results. A later composition gets its own ticket and generation.
  func deactivate() {
    assertMainQueue()
    connectionPolicy.deactivate()
    if isSecureInputEnabled() { clearCache() }
    failAllPending(with: CandidateTranslationFailure.cancelled)
    closeConnection()
  }

  func invalidate() {
    assertMainQueue()
    connectionPolicy.deactivate()
    clearCache()
    failAllPending(with: CandidateTranslationFailure.cancelled)
    closeConnection()
  }

  private func clearCache() {
    cacheExpiry?.cancel()
    cacheExpiry = nil
    cache.removeAll()
  }

  private func scheduleCacheExpiry() {
    guard cacheExpiry == nil, let deadline = cache.nextExpiration else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.cacheExpiry = nil
      self.cache.removeExpired(at: self.now())
      self.scheduleCacheExpiry()
    }
    cacheExpiry = work
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now()), execute: work)
  }

  private func closeConnection() {
    idleDisconnect?.cancel()
    idleDisconnect = nil
    connection?.invalidationHandler = nil
    connection?.interruptionHandler = nil
    connection?.invalidate()
    connection = nil
  }

  private func scheduleIdleDisconnect() {
    // Keep one timer. It rechecks last activity rather than allocating a new
    // ten-minute work item for every key or cache hit.
    guard idleDisconnect == nil, connection != nil,
          let delay = connectionPolicy.disconnectDelay(at: now(),
                                                        hasPendingRequests: !pending.isEmpty) else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.idleDisconnect = nil
      guard let remaining = self.connectionPolicy.disconnectDelay(at: self.now(),
                                                                   hasPendingRequests: !self.pending.isEmpty) else { return }
      guard remaining == 0 else { self.scheduleIdleDisconnect(); return }
      self.closeConnection() // Keep bounded results while letting the worker exit.
    }
    idleDisconnect = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func proxy(errorHandler: ((Error) -> Void)? = nil) -> RoarkTTranslationXPCProtocol? {
    if let proxyProvider { return proxyProvider() }
    let connection = connection ?? makeConnection()
    return connection.remoteObjectProxyWithErrorHandler { error in
      errorHandler?(error)
    } as? RoarkTTranslationXPCProtocol
  }

  private func makeConnection() -> NSXPCConnection {
    let connection = NSXPCConnection(machServiceName: ROARKT_TRANSLATION_SERVICE_NAME, options: [])
    connection.setCodeSigningRequirement(
      "anchor apple generic and certificate leaf[subject.OU] = \"\(ROARKT_TEAM_ID)\" and identifier \"\(ROARKT_TRANSLATION_SERVICE_NAME)\""
    )
    connection.remoteObjectInterface = NSXPCInterface(with: RoarkTTranslationXPCProtocol.self)
    let token = UUID()
    connectionToken = token
    connection.interruptionHandler = { [weak self] in
      DispatchQueue.main.async { self?.connectionInterrupted(token) }
    }
    connection.invalidationHandler = { [weak self] in
      DispatchQueue.main.async { self?.connectionInvalidated(token) }
    }
    connection.resume()
    self.connection = connection
    return connection
  }

  private func cancellationProxy() -> RoarkTTranslationXPCProtocol? {
    if let proxyProvider { return proxyProvider() }
    guard let connection else { return nil }
    return connection.remoteObjectProxyWithErrorHandler { _ in } as? RoarkTTranslationXPCProtocol
  }

  private func connectionInterrupted(_ token: UUID) {
    guard connection != nil, connectionToken == token else { return }
    connection = nil
    failAllPending(with: CandidateTranslationFailure.serviceUnavailable)
  }

  private func connectionInvalidated(_ token: UUID) {
    guard connection != nil, connectionToken == token else { return }
    connection = nil
    failAllPending(with: CandidateTranslationFailure.serviceUnavailable)
  }

  private func failAllPending(with error: Error) {
    let requests = Array(pending.values)
    pending.removeAll()
    for request in requests {
      request.timeout.cancel()
      request.completion(.failure(error))
    }
  }

  private func finish(
    sessionID: String,
    generation: Int64,
    result: Result<RoarkTTranslationResult, Error>
  ) {
    assertMainQueue()
    guard let request = pending[sessionID], request.generation == generation else { return }
    request.timeout.cancel()
    pending[sessionID] = nil
    guard !isSecureInputEnabled() else {
      clearCache()
      scheduleIdleDisconnect()
      request.completion(.failure(CandidateTranslationFailure.cancelled))
      return
    }
    if case let .success(response) = result,
       request.request.accepts(source: response.sourceText, direction: response.direction) {
      cache.insert(response.translatedText, for: request.request, now: now())
    }
    scheduleCacheExpiry()
    scheduleIdleDisconnect()
    request.completion(result)
  }

  private func assertMainQueue() {
    dispatchPrecondition(condition: .onQueue(.main))
  }

}
