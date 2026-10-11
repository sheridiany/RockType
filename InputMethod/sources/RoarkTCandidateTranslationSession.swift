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

enum RoarkTInputAIAction: String, CaseIterable {
  case rewrite, polish, translate
  var title: String {
    switch self { case .rewrite: return "AI 改写"; case .polish: return "AI 润色"; case .translate: return "AI 翻译" }
  }
  static func matches(keyCode: UInt16, modifiers: Shortcut.Modifiers, shortcut: Shortcut) -> Bool {
    guard modifiers == shortcut.modifiers, !modifiers.intersection([.control, .option, .command]).isEmpty,
          let key = shortcut.key?.lowercased() else { return false }
    // Same physical US key names as the settings recorder; Shift must not turn "1" into "!".
    let codes: [String: UInt16] = [
      "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
      "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
      "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
      "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
      "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
      "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51,
      "left": 123, "right": 124, "down": 125, "up": 126
    ]
    return codes[key] == keyCode
  }
  static func failure(_ error: Error) -> (message: String, retryable: Bool) {
    let value = error as NSError
    if value.domain == CandidateTranslationFailure.errorDomain {
      switch value.code {
      case 101: return ("未配置 AI，请到设置启用并配置 AI", false)
      case 103, 105: return ("AI 已取消", false)
      case 104: return ("AI 连接身份验证失败", false)
      case 106: return ("AI 请求超时，按 Tab 重试", true)
      case 107: return ("AI 认证失败，请检查设置中的密钥", false)
      case 108: return ("AI 模型不可用，请检查设置", false)
      case 109: return ("AI 请求限流，按 Tab 重试", true)
      case 110: return ("AI 网络失败，按 Tab 重试", true)
      case 100, 102, 111, 112: return ("AI 请求失败，请重新触发", false)
      default: break
      }
    }
    let failure = CandidateTranslationFailure.from(error)
    return ("AI 请求失败：" + failure.message, failure.canRetry)
  }

  var next: Self { switch self { case .rewrite: return .polish; case .polish: return .translate; case .translate: return .rewrite } }
}

struct RoarkTCandidateTranslationSession {
  struct Ticket: Equatable {
    let generation: Int64
    let snapshot: RoarkTCandidateSnapshot
    var action: RoarkTInputAIAction? = nil
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
  var interceptsTab: Bool { ticket != nil && (isLoading || commit != nil || canRetry || ticket?.action != nil) }

  var displayText: String {
    guard ticket != nil else { return "" }
    if let action = ticket?.action {
      return action.title + " · " + (isLoading ? "思考中…" : (translation ?? failure ?? "暂不可用"))
    }
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

  mutating func beginAI(_ snapshot: RoarkTCandidateSnapshot) -> Ticket {
    let action = ticket?.snapshot == snapshot ? (ticket?.action?.next ?? .rewrite) : .rewrite
    return begin(snapshot, action: action)
  }

  private mutating func begin(_ snapshot: RoarkTCandidateSnapshot, action: RoarkTInputAIAction? = nil) -> Ticket {
    let previousText = translation
    invalidate()
    translation = action == nil ? previousText : nil
    let request = Ticket(generation: generation, snapshot: snapshot, action: action)
    ticket = request
    isLoading = true
    return request
  }

  mutating func retry() -> Ticket? {
    guard canRetry, !isLoading, let ticket else { return nil }
    return begin(ticket.snapshot, action: ticket.action)
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
