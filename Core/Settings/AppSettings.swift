import Foundation

/// Persisted preferences only. Credentials and permission/connection-test results are runtime state.
public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var general = GeneralSettings()
    public var input = InputSettings()
    public var translation = TranslationSettings()
    public var voice = VoiceSettings()
    public var selection = SelectionSettings()
    public var screenshot = ScreenshotSettings()
    public var ai = AIConnectionSettings()
    public var templates = OperationTemplate.defaults
    public var shortcuts = ShortcutSettings()
    public var privacy = PrivacySettings()
    public init() {}
    public static let defaults = AppSettings()
}

public struct GeneralSettings: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, Sendable { case system, light, dark }
    public var showBeijingTime = false
    public var launchAtLogin = false
    public var appearance: Appearance = .system
    public var language = "system"
    public var onboardingCompleted = false
    public init() {}
}

public struct InputSettings: Codable, Equatable, Sendable {
    public enum Scheme: String, Codable, Sendable { case pinyin = "roarkt", flypy = "roarkt_flypy" }
    public var scheme: Scheme = .pinyin
    public var fuzzyPinyin = true
    public var abbreviatedPinyin = true
    public var spellingCorrection = true
    public var shiftTogglesLanguage = true
    public var showModeIndicator = true
    public var candidateTranslation = true
    public var englishCompletion = true
    public var simplifiedChinese = true
    /// Optional so existing schema-1 preferences decode without resetting input settings.
    public var inputAI: InputAISettings? = nil
    public init() {}
}

public struct TranslationSettings: Codable, Equatable, Sendable {
    public enum Engine: String, Codable, Sendable { case offlineFirst, ai }
    public var engine: Engine = .offlineFirst
    /// "auto" means Chinese ↔ English; otherwise a language identifier.
    public var targetLanguage = "auto"
    public var allowCandidateAI = false
    /// nil follows the connection's default model.
    public var model: String? = nil
    public init() {}
}

public struct VoiceSettings: Codable, Equatable, Sendable {
    public enum Model: String, Codable, Sendable { case small = "0.6B-8bit", large = "1.7B-8bit" }
    public var model: Model = .small
    public var automaticallyPrepareModel = false
    public var polishWithAI = false
    public init() {}
}

public struct SelectionSettings: Codable, Equatable, Sendable {
    public enum Trigger: String, Codable, Sendable { case selection, shortcutOnly }
    public enum ApplicationFilter: String, Codable, Sendable { case blacklist, whitelist }
    public var trigger: Trigger = .selection
    public var applicationFilter: ApplicationFilter = .blacklist
    public var excludedApplications = ["com.apple.finder"]
    public var includedApplications: [String] = []
    public var toolbarActions = ["translate", "summarize", "polish", "explain", "search"]
    public var disabledActions: [String] = []
    public var followToolbar = true
    public var automaticallyClose = true
    public var automaticallyPin = false
    public var windowOpacity = 1.0
    public var searchEngine = "https://www.google.com/search?q={query}"
    public var assistantModel: String? = nil
    public init() {}
}

public struct ScreenshotSettings: Codable, Equatable, Sendable {
    public enum Format: String, Codable, Sendable { case png, jpeg }
    public var format: Format = .png
    public var ocrLanguages = ["zh-Hans", "en-US"]
    public init() {}
}

public struct AIConnectionSettings: Codable, Equatable, Sendable {
    /// Stable Keychain account, not a credential. One connection in this product version.
    public var id = "default"
    public var name = ""
    public var baseURL = ""
    public var defaultModel = ""
    public var defaultModelSupportsImages = false
    public var visionModel: String? = nil
    public init() {}
}

public struct OperationTemplate: Codable, Equatable, Sendable, Identifiable {
    public enum Input: String, Codable, Sendable { case text, image }
    public enum Output: String, Codable, Sendable { case comparison, text, markdown }
    public var id: String
    public var name: String
    public var icon: String
    public var prompt: String
    public var input: Input
    public var model: String?
    public var output: Output
    public init(id: String = UUID().uuidString, name: String, icon: String, prompt: String,
                input: Input = .text, model: String? = nil, output: Output = .markdown) {
        self.id = id; self.name = name; self.icon = icon; self.prompt = prompt
        self.input = input; self.model = model; self.output = output
    }
    public static let defaults: [OperationTemplate] = [
        .init(id: "translate", name: "翻译", icon: "character.bubble", prompt: "请将以下内容翻译为 {{target}}，保留段落、列表和代码块。", output: .comparison),
        .init(id: "summarize", name: "总结", icon: "text.alignleft", prompt: "请用中文总结以下内容的要点。"),
        .init(id: "polish", name: "润色", icon: "pencil", prompt: "请润色以下内容，保留原意。", output: .text),
        .init(id: "explain", name: "解释", icon: "questionmark.bubble", prompt: "请用中文解释以下内容。"),
    ]
}

public struct ShortcutSettings: Codable, Equatable, Sendable {
    public var bindings = Shortcut.defaults
    /// No default until the IME AI gesture is decided in M6.
    public var inputMethodAI: Shortcut? = nil
    public var showSettings: Shortcut? = nil
    public init() {}
}

public struct PrivacySettings: Codable, Equatable, Sendable {
    public var keepRecentResultsInMemory = true
    // Disk history, continuous clipboard monitoring and bypassing Secure Input are not supported.
    public init() {}
}

/// Explicit IME actions only; this does not opt into automatic candidate AI translation.
public struct InputAISettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var shortcut: Shortcut? = Shortcut(key: "tab", modifiers: .option)
    public var timeout: TimeInterval = 30
    public init() {}
}
