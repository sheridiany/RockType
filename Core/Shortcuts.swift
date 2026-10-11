/// Default global shortcuts (ADR-0002). User overrides live in settings (FR-E7).
public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case voiceHoldToTalk
    case screenshot
    case translateSelection
    case summarizeSelection
}

public struct Shortcut: Equatable, Codable, Sendable {
    public struct Modifiers: OptionSet, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let command = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
        public static let function = Modifiers(rawValue: 1 << 4)
    }

    /// Key character, or nil for a modifier-only shortcut such as holding Fn.
    public var key: String?
    public var modifiers: Modifiers

    public init(key: String?, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let defaults: [ShortcutAction: Shortcut] = [
        .voiceHoldToTalk: Shortcut(key: nil, modifiers: .function),
        .screenshot: Shortcut(key: "1", modifiers: .control),
        .translateSelection: Shortcut(key: "t", modifiers: [.control, .option]),
        .summarizeSelection: Shortcut(key: "s", modifiers: [.control, .option]),
    ]
}
