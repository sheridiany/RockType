import Foundation

/// Disk boundary for the application's single SettingsStore. No credential storage.
public struct SettingsPersistence: Sendable {
    public enum Failure: Error, Equatable { case unsupportedSchema(Int), invalidValues }
    public enum LoadStatus: Equatable, Sendable {
        case loaded, missing, recovered(corruptFile: URL)
    }
    public struct Loaded: Sendable {
        public let settings: AppSettings
        public let status: LoadStatus
    }
    public let fileURL: URL
    public init(fileURL: URL = defaultURL) { self.fileURL = fileURL }
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Identifiers.applicationSupportFolder, isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public func load() throws -> Loaded {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch CocoaError.fileReadNoSuchFile { return Loaded(settings: .defaults, status: .missing) }
        do {
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            try Self.validate(settings)
            return Loaded(settings: settings, status: .loaded)
        } catch {
            // Never overwrite the only copy of an unreadable configuration.
            let backup = fileURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)")
            try data.write(to: backup, options: .withoutOverwriting)
            try Self.protect(backup)
            try save(.defaults)
            return Loaded(settings: .defaults, status: .recovered(corruptFile: backup))
        }
    }

    public func save(_ settings: AppSettings) throws {
        try Self.validate(settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL, options: .atomic)
        try Self.protect(fileURL)
    }

    private static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func validate(_ settings: AppSettings) throws {
        guard settings.schemaVersion == 1 else { throw Failure.unsupportedSchema(settings.schemaVersion) }
        guard settings.selection.windowOpacity.isFinite,
              (0.2...1).contains(settings.selection.windowOpacity),
              Set(settings.templates.map(\.id)).count == settings.templates.count,
              !settings.ai.id.isEmpty else { throw Failure.invalidValues }
    }
}
