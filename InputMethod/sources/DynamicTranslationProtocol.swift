// Independently compiled input-method value types. See LICENSE.translation.txt.
import Foundation

public enum DynamicTranslationPolicy {
    // Product policy for the Chinese/English candidate channel, not general
    // language detection: Han wins in mixed text; Latin text maps to English.
    public static func direction(for source: String) -> DynamicTranslationDirection? {
        if source.range(of: "\\p{Han}", options: .regularExpression) != nil {
            return .chineseToEnglish
        }
        if source.range(of: "\\p{Latin}", options: .regularExpression) != nil,
           source.range(of: "[\\p{L}&&[^\\p{Latin}]]", options: .regularExpression) == nil {
            return .englishToChinese
        }
        return nil
    }

    public static func shouldTranslate(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }
}

public enum DynamicTranslationDirection: String, Sendable {
    case chineseToEnglish = "zh-en"
    case englishToChinese = "en-zh"
}

public enum CandidateTranslationFailure: Int, Error, CustomNSError, LocalizedError, Sendable {
    case invalidRequest = 1
    case cancelled = 4
    case unauthorized = 5
    case incompatibleVersion = 6
    case languagePackMissing = 10
    case requiresMacOS26 = 11
    case serviceUnavailable = 12
    case timedOut = 13
    case unsupportedLanguage = 14
    case invalidResponse = 15

    public static var errorDomain: String { "com.roarkist.roarkt.translation" }
    public var errorCode: Int { rawValue }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: message] }
    public var errorDescription: String? { message }
    public var canRetry: Bool { self == .serviceUnavailable || self == .timedOut }
    public var message: String {
        switch self {
        case .invalidRequest: "当前候选不适用于中英翻译"
        case .cancelled: "翻译已取消"
        case .unauthorized: "翻译权限校验失败，请完成输入法升级"
        case .incompatibleVersion: "翻译服务版本不兼容，请完成升级"
        case .languagePackMissing: "请先在设置中准备中英翻译语言包"
        case .requiresMacOS26: "动态翻译需要 macOS 26 或更新版本"
        case .serviceUnavailable: "翻译服务暂不可用"
        case .timedOut: "翻译超时"
        case .unsupportedLanguage: "不支持当前语言或语言组合"
        case .invalidResponse: "翻译响应与当前候选不匹配"
        }
    }

    public static func from(_ error: Error) -> Self {
        if error is CancellationError { return .cancelled }
        let error = error as NSError
        if error.domain == errorDomain {
            if error.code == 2 || error.code == 3 { return .cancelled }
            if let known = Self(rawValue: error.code) { return known }
        }
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return .cancelled }
        return .serviceUnavailable
    }
}

// Compiled into both the input method and service: one wire contract and one
// source-language policy. Input-code heuristics are never part of this contract.
public struct CandidateTranslationRequest: Equatable, Sendable {
    public enum Scope: String, Sendable { case whole, segment }
    public enum ValidationError: Error { case unsupportedVersion, invalidRequest }
    public static let version = "2"
    public static let maximumTextLength = 4_096
    public let rawInput: String
    public let sourceText: String
    public let identity: String
    public let scope: Scope
    public let direction: DynamicTranslationDirection

    public init(rawInput: String, sourceText: String, identity: String, scope: Scope) throws {
        guard let direction = DynamicTranslationPolicy.direction(for: sourceText) else {
            throw ValidationError.invalidRequest
        }
        try self.init(payload: ["version": Self.version, "rawInput": rawInput, "sourceText": sourceText,
                               "identity": identity, "scope": scope.rawValue, "direction": direction.rawValue])
    }

    public init(payload: [String: String]) throws {
        guard payload["version"] == Self.version else { throw ValidationError.unsupportedVersion }
        guard payload.count == 6,
              let raw = payload["rawInput"], !raw.isEmpty, raw.utf8.count <= Self.maximumTextLength,
              let source = payload["sourceText"], !source.isEmpty, source.utf8.count <= Self.maximumTextLength,
              let identity = payload["identity"], identity.utf8.count <= 128,
              let scope = payload["scope"].flatMap(Scope.init(rawValue:)),
              let direction = payload["direction"].flatMap(DynamicTranslationDirection.init(rawValue:)),
              DynamicTranslationPolicy.direction(for: source) == direction else {
            throw ValidationError.invalidRequest
        }
        let bounds = identity.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard bounds.count == 3, identity.split(separator: ":", omittingEmptySubsequences: false).count == 3,
              bounds[0] >= 0, bounds[1] > bounds[0], bounds[1] <= raw.utf8.count, bounds[2] >= 0 else {
            throw ValidationError.invalidRequest
        }
        rawInput = raw
        sourceText = source
        self.identity = identity
        self.scope = scope
        self.direction = direction
    }

    // Tiny curated fallback, matched by selected text, never by input code.
    // Keep this table independent of the deprecated numbered-candidate pipeline.
    private static let staticPairs: [(chinese: String, english: String)] = [
        ("你好", "hello"), ("谢谢", "thanks"), ("早上好", "good morning"),
        ("晚安", "good night"), ("再见", "goodbye"), ("世界", "world"),
        ("输入法", "input method"), ("中文", "Chinese"), ("英文", "English"), ("测试", "test")
    ]

    public var staticTranslation: String? {
        switch direction {
        case .chineseToEnglish:
            return Self.staticPairs.first { $0.chinese == sourceText }?.english
        case .englishToChinese:
            let key = sourceText.lowercased()
            if let pair = Self.staticPairs.first(where: { $0.english.lowercased() == key }) { return pair.chinese }
            // Explicit historical aliases, not fuzzy whitespace/pinyin matching.
            return ["thank you": "谢谢", "thankyou": "谢谢", "goodmorning": "早上好",
                    "goodnight": "晚安", "inputmethod": "输入法"][key]
        }
    }

    public var payload: [String: String] {
        ["version": Self.version, "rawInput": rawInput, "sourceText": sourceText,
         "identity": identity, "scope": scope.rawValue, "direction": direction.rawValue]
    }

    public func accepts(source: String, direction: String) -> Bool {
        source == sourceText && direction == self.direction.rawValue
    }
}
