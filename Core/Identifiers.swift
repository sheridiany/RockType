import Foundation

/// Single source of identifiers for Swift code. Mirrors Shared/XPCProtocol/include/RoarkTIdentifiers.h.
public enum Identifiers {
    public static let teamID = "DF7J2VBQD8"
    public static let appBundleID = "com.roarkist.roarkt"
    public static let inputMethodBundleID = "com.roarkist.inputmethod.RoarkT"
    public static let pinyinInputSourceID = "com.roarkist.inputmethod.RoarkT.pinyin"
    public static let flypyInputSourceID = "com.roarkist.inputmethod.RoarkT.flypy"
    public static let translationServiceName = "com.roarkist.roarkt.translation"
    public static let voiceWorkerID = "com.roarkist.roarkt.voice"
    public static let dictationEndpointName = "com.roarkist.inputmethod.RoarkT.dictation"
    public static let keychainService = "com.roarkist.roarkt.ai"
    public static let applicationSupportFolder = "RoarkT"

    /// Opt-in screenshot archive; separate from the internal settings directory.
    public static func screenshotHistoryDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/RockType/ScreenshotHistory", isDirectory: true)
    }

    /// Private Rime profile; callers may inject a temporary home for verification.
    public static func rimeUserDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(applicationSupportFolder, isDirectory: true)
            .appendingPathComponent("Rime", isDirectory: true)
    }

    /// Seed installation metadata before librime's first maintenance so sync never falls
    /// back to a working-directory-relative location. No existing profile is imported.
    public static func prepareRimeDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let directory = rimeUserDirectory(home: home)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installation = directory.appendingPathComponent("installation.yaml")
        if !FileManager.default.fileExists(atPath: installation.path) {
            // JSON strings are also YAML scalars and safely quote spaces and apostrophes.
            let path = directory.appendingPathComponent("sync", isDirectory: true).path
            let quoted = String(decoding: try JSONEncoder().encode(path), as: UTF8.self)
            try Data("sync_dir: \(quoted)\n".utf8).write(to: installation, options: .withoutOverwriting)
        }
    }

    /// Code requirement for an XPC peer with the given signing identifier.
    public static func codeRequirement(for identifier: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(identifier)\""
    }
}
