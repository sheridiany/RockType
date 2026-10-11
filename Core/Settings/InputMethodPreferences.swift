import Foundation

/// Payload-free invalidation signals; identifiers derive from the product's canonical namespace.
public enum InputMethodSettingsNotification {
    public static let changed = Notification.Name(Identifiers.appBundleID + ".settingsChanged")
    public static let redeploy = Notification.Name(Identifiers.appBundleID + ".redeployRime")
}

/// Read-only projection: the input method never parses AI, voice or content-bearing template fields.
public struct InputMethodPreferences: Decodable, Equatable, Sendable {
    public var input: InputSettings
    public var translation: TranslationSettings
    public static let defaults = Self(input: InputSettings(), translation: TranslationSettings())
    public init(input: InputSettings, translation: TranslationSettings) {
        self.input = input; self.translation = translation
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, input, translation }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported settings schema")
        }
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
