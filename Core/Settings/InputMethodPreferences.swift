import Foundation

/// Payload-free invalidation signals; identifiers derive from the product's canonical namespace.
public enum InputMethodSettingsNotification {
    public static let changed = Notification.Name(Identifiers.appBundleID + ".settingsChanged")
    public static let redeploy = Notification.Name(Identifiers.appBundleID + ".redeployRime")
}

/// Read-only projection: the input method never parses AI connection, voice or content-bearing template fields.
public struct InputMethodPreferences: Decodable, Equatable, Sendable {
    public var input: InputSettings
    public var translation: TranslationSettings
    /// Feature-level gate; missing features/keys retain the established input-AI settings.
    public var inputMethodAIEnabled: Bool
    public var allowsInputAI: Bool { inputMethodAIEnabled && input.inputAI?.enabled == true }
    public static let defaults = Self(input: InputSettings(), translation: TranslationSettings())
    public init(input: InputSettings, translation: TranslationSettings, inputMethodAIEnabled: Bool = true) {
        self.input = input; self.translation = translation; self.inputMethodAIEnabled = inputMethodAIEnabled
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, input, translation, features }
    // Only this flag belongs to the IME. Other feature payloads cannot reset its preferences.
    private struct Features: Decodable { var inputMethodAI: Bool? }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported settings schema")
        }
        inputMethodAIEnabled = try values.decodeIfPresent(Features.self, forKey: .features)?.inputMethodAI ?? true
        input = try values.decodeIfPresent(InputSettings.self, forKey: .input) ?? InputSettings()
        translation = try values.decodeIfPresent(TranslationSettings.self, forKey: .translation) ?? TranslationSettings()
    }
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Identifiers.applicationSupportFolder)
            .appendingPathComponent("settings.json")
    }
    public static func decode(_ data: Data) -> Self {
        (try? JSONDecoder().decode(Self.self, from: data)) ?? .defaults
    }
    /// No backup, directory creation or repair writes in the input method.
    public static func load(from url: URL = defaultURL) -> Self {
        guard let file = try? FileHandle(forReadingFrom: url) else { return .defaults }
        defer { try? file.close() }
        let limit = 1_048_576
        guard let data = try? file.read(upToCount: limit + 1), data.count <= limit else { return .defaults }
        return decode(data)
    }
}
