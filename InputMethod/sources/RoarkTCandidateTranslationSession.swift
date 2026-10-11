import Foundation

struct RoarkTCandidateSnapshot: Equatable {
  let rawInput: String
  let source: String
  // Rime segment bounds and absolute selected index; valid only for this input.
  let identity: String
  let scope: String

  func isSelected(index: Int, pageSize: Int) -> Bool {
    guard pageSize > 0, index >= 0, index < pageSize,
          let selected = Int(identity.split(separator: ":").last ?? ""), selected >= 0 else { return false }
    return selected % pageSize == index
  }

  /// Conservative local protection. Mixed prose containing a technical token stays intact;
  /// no placeholders or identifiers are sent to the translator and then guessed back.
  static func preservesTechnicalText(_ text: String) -> Bool {
    let tokens = text.lowercased().components(separatedBy: technicalTokenCharacters.inverted)
    if tokens.contains(where: technicalNames.contains) { return true }
    return technicalPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  private static let technicalNames: Set<String> = ["swiftui", "xcode", "github", "gitlab", "openai", "anthropic",
    "qwen", "qwen3", "mlx", "json", "yaml", "api", "sdk", "gpt", "claude", "rocktype",
    "kubernetes", "docker", "postgresql", "typescript", "javascript"]
  private static let technicalTokenCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
  private static let technicalPattern = try! NSRegularExpression(pattern:
    "C\\+\\+|C#|[a-z][A-Z]|[A-Z]{2,}[a-z]|[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+|[A-Za-z][A-Za-z0-9]*\\.[A-Za-z][A-Za-z0-9]*|[A-Za-z][A-Za-z0-9]*\\(\\)|\\b[A-Z]{2,16}\\b")

  var translationRequest: CandidateTranslationRequest? {
    guard let scope = CandidateTranslationRequest.Scope(rawValue: scope) else { return nil }
    return try? CandidateTranslationRequest(rawInput: rawInput, sourceText: source, identity: identity, scope: scope)
  }
}

struct RoarkTCandidateTranslationSession {
  struct Ticket: Equatable {
    let generation: Int64
    let snapshot: RoarkTCandidateSnapshot
  }
  struct Submission {
    let snapshot: RoarkTCandidateSnapshot
    let text: String
  }

  private(set) var ticket: Ticket?
  private(set) var isLoading = false
  private(set) var failure: String?
  private(set) var canRetry = false
  private(set) var direction: String?
  private var translation: String?
  private var loadingIndicatorVisible = false
  private var generation: Int64 = 0

  var commit: Submission? {
    guard let ticket, let translation, !isLoading, failure == nil else { return nil }
    return Submission(snapshot: ticket.snapshot, text: translation)
  }

  // Keep loading Tab local even with no retained text: it must not change
  // candidate selection or move application focus while awaiting this ticket.
  var interceptsTab: Bool { ticket != nil && (isLoading || commit != nil || canRetry) }

  var displayText: String {
    guard ticket != nil else { return "" }
    if isLoading { return loadingIndicatorVisible ? "正在翻译…" : (translation ?? "") }
    return translation ?? (failure ?? "暂不可用") + (canRetry ? "，按 Tab 重试" : "")
  }

  @discardableResult
  mutating func showLoadingIndicator(for request: Ticket) -> Bool {
    guard ticket == request, isLoading else { return false }
    loadingIndicatorVisible = true
    return true
  }

  mutating func observe(_ snapshot: RoarkTCandidateSnapshot) -> Ticket? {
    guard ticket?.snapshot != snapshot else { return nil }
    return begin(snapshot)
  }

  private mutating func begin(_ snapshot: RoarkTCandidateSnapshot) -> Ticket {
    let previousText = translation
    invalidate()
    translation = previousText
    let request = Ticket(generation: generation, snapshot: snapshot)
    ticket = request
    isLoading = true
    return request
  }

  mutating func retry() -> Ticket? {
    guard canRetry, !isLoading, let ticket else { return nil }
    return begin(ticket.snapshot)
  }

  @discardableResult
  mutating func receive(_ text: String, for request: Ticket, direction: String? = nil) -> Bool {
    guard ticket == request, isLoading, !text.isEmpty else { return false }
    translation = text
    self.direction = direction
    isLoading = false
    failure = nil
    return true
  }

  @discardableResult
  mutating func fail(_ failure: CandidateTranslationFailure, for request: Ticket) -> Bool {
    guard ticket == request, isLoading else { return false }
    switch failure {
    case .requiresMacOS26, .languagePackMissing, .serviceUnavailable, .timedOut:
      if let candidate = request.snapshot.translationRequest, let text = candidate.staticTranslation {
        return receive(text, for: request, direction: candidate.direction.rawValue)
      }
    default:
      break // Never hide cancellation, authorization, protocol or invalid-response failures.
    }
    let message = failure == .requiresMacOS26
      ? "无匹配的静态译文；动态翻译需 macOS 26"
      : failure.message
    return fail(message, for: request, retryable: failure.canRetry)
  }

  @discardableResult
  mutating func fail(_ message: String, for request: Ticket, retryable: Bool = true) -> Bool {
    guard ticket == request, isLoading else { return false }
    canRetry = retryable
    translation = nil
    isLoading = false
    failure = message
    return true
  }

  mutating func invalidate() {
    loadingIndicatorVisible = false
    generation += 1
    canRetry = false
    direction = nil
    ticket = nil
    translation = nil
    isLoading = false
    failure = nil
  }
}

// One owned allocation per controller; read strings before reusing C storage.
final class RoarkTRimePropertyReader {
  private var buffer: [CChar]

  init(capacity: Int = 16_384) {
    precondition(capacity > 0)
    buffer = .init(repeating: 0, count: capacity)
  }

  func read(_ names: [String], fetch: (String, UnsafeMutablePointer<CChar>, Int) -> Bool) -> [String: String] {
    var values: [String: String] = [:]
    for name in names {
      buffer.withUnsafeMutableBufferPointer { storage in
        // Reject a success without a terminator, including exactly full buffers.
        storage.update(repeating: 1)
        guard fetch(name, storage.baseAddress!, storage.count), storage.contains(0) else { return }
        values[name] = String(cString: storage.baseAddress!)
      }
    }
    return values
  }
}
