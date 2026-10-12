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
    /// Additional connection profiles. Secrets remain in Keychain under each profile's id.
    public var aiProviders: [AIConnectionSettings]? = nil
    public var aiTaskRoutes: [String: AITaskRoute]? = nil
    public var templates = OperationTemplate.defaults
    public var shortcuts = ShortcutSettings()
    public var privacy = PrivacySettings()
    public init() {}
    public static let defaults = AppSettings()
}

public struct GeneralSettings: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, Sendable { case system, light, dark }
    public var showBeijingTime = false
    /// Optional so settings written before this field still decode. nil means hidden:
    /// RockType opens from the input method menu or Launchpad, not from the menu bar.
    public var menuBarIcon: Bool? = nil
    /// The status item exists only when asked for; the Beijing clock lives in it.
    public var showsMenuBarItem: Bool { (menuBarIcon ?? false) || showBeijingTime }
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
    public var cleanUpLocally = true
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case model, automaticallyPrepareModel, polishWithAI, cleanUpLocally
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        model = try values.decode(Model.self, forKey: .model)
        automaticallyPrepareModel = try values.decode(Bool.self, forKey: .automaticallyPrepareModel)
        polishWithAI = try values.decode(Bool.self, forKey: .polishWithAI)
        cleanUpLocally = try values.decodeIfPresent(Bool.self, forKey: .cleanUpLocally) ?? true
    }
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
    /// nil uses ~/Pictures/RockType. Set only through the directory picker.
    public var saveDirectory: String? = nil
    /// Missing in existing settings: each tool uses its own built-in default.
    public var annotationStyles: [String: ScreenshotAnnotationStyle]? = nil
    /// nil/false asks before each explicit image AI action; no image content is persisted.
    public var skipImageAIConfirmation: Bool? = nil
    /// nil keeps the default rounded output when loading settings written before this option.
    public var roundedCorners: Bool? = nil
    /// nil retains 10 recent closed pins; zero disables retention. Images never persist to disk.
    public var pinHistoryLimit: Int? = nil
    public var historyOnDisk: Bool? = nil
    public var historyDiskCount: Int? = nil
    public var historyDiskDays: Int? = nil
    public init() {}
}

public struct AIConnectionSettings: Codable, Equatable, Sendable {
    /// Stable Keychain account for this provider, never a credential.
    public var id = "default"
    public var name = ""
    public var baseURL = ""
    public var defaultModel = ""
    public var defaultModelSupportsImages = false
    public var visionModel: String? = nil
    /// Explicit opt-in only; a failed request may retry this model on the SAME provider.
    public var fallbackModel: String? = nil
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
    public var shortcut: Shortcut?
    public var showInScreenshot: Bool?
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
    /// Missing means new group actions use defaults; true allows an explicitly cleared binding.
    public var screenshotGroupDefaultsApplied: Bool? = nil
    public init() {}
}

public struct PrivacySettings: Codable, Equatable, Sendable {
    public var keepRecentResultsInMemory = true
    // This controls text results only; screenshot disk history has a separate explicit opt-in.
    public init() {}
}

/// Explicit IME actions only; this does not opt into automatic candidate AI translation.
public struct InputAISettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var shortcut: Shortcut? = Shortcut(key: "tab", modifiers: .option)
    public var timeout: TimeInterval = 30
    public init() {}
}

/// Preferences only: never contains annotation text, geometry or captured pixels.
public struct ScreenshotAnnotationStyle: Codable, Equatable, Sendable {
    public var colorHex: String
    public var width: Double
    public var textBackground: Bool?
    public init(colorHex: String = "D84A2F", width: Double = 5, textBackground: Bool? = nil) {
        self.colorHex = colorHex; self.width = width; self.textBackground = textBackground
    }
}

public struct AITaskRoute: Codable, Equatable, Sendable {
    public var providerID: String
    public var model: String?
    public init(providerID: String, model: String? = nil) { self.providerID = providerID; self.model = model }
}
