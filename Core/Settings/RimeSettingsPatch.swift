import Foundation
import Darwin

/// Only patch existing schema entries; never copy the GPL double-pinyin algebra into the app.
public enum RimeSettingsPatch {
    public static let marker = "# 由 RoarkT 生成；请通过 RoarkT 设置修改。"
    public static let fileNames = ["roarkt.custom.yaml", "roarkt_flypy.custom.yaml"]

    public static func yaml(for scheme: InputSettings.Scheme, settings: InputSettings) -> String {
        let shift = settings.shiftTogglesLanguage ? "commit_code" : "noop"
        var lines = [marker, "patch:",
            "  \"ascii_composer/switch_key/Shift_L\": \(shift)",
            "  \"ascii_composer/switch_key/Shift_R\": \(shift)",
            "  \"english/enable_completion\": \(settings.englishCompletion)"]
        // Stable indices from the shipped 0.3.0 schemas; tests deploy the patches against those schemas.
        // Identity substitutions disable optional rules without shifting the double-pinyin encoding rules.
        var disabled: [Int] = []
        if !settings.fuzzyPinyin { disabled += scheme == .pinyin ? Array(0...5) : Array(1...6) }
        if scheme == .pinyin {
            if !settings.abbreviatedPinyin { disabled += Array(6...7) }
            if !settings.spellingCorrection { disabled += Array(8...17) }
            lines.append("  \"translator/enable_correction\": \(settings.spellingCorrection)")
        }
        for index in disabled.sorted() {
            lines.append("  \"speller/algebra/@\(index)\": 'xform/^(.+)$/$1/'")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// The main app owns these files. User-owned or symlinked destinations are never replaced.
public struct RimeSettingsPatchWriter: Sendable {
    public struct Result: Equatable, Sendable {
        public var changed: Bool
        public var conflicts: [String]
    }
    public let directory: URL
    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Rime")) {
        self.directory = directory
    }

    public func write(_ settings: InputSettings) throws -> Result {
        let schemes: [InputSettings.Scheme] = [.pinyin, .flypy]
        let pending = try zip(RimeSettingsPatch.fileNames, schemes).map { name, scheme -> (URL, Data, Data?, Bool) in
            let url = directory.appendingPathComponent(name)
            let data = Data(RimeSettingsPatch.yaml(for: scheme, settings: settings).utf8)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let attributes, attributes[.type] as? FileAttributeType != .typeRegular { return (url, data, nil, true) }
            let existing: Data?
            do { existing = try Data(contentsOf: url) }
            catch CocoaError.fileReadNoSuchFile { existing = nil }
            let owned = existing == nil || existing!.starts(with: Data((RimeSettingsPatch.marker + "\n").utf8))
            return (url, data, existing, !owned)
        }
        let conflicts = pending.filter { $0.3 }.map { $0.0.lastPathComponent }
        // Validate both destinations before touching either, so a conflict cannot partially apply preferences.
        guard conflicts.isEmpty else { return Result(changed: false, conflicts: conflicts) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var changed = false
        for (url, data, existing, _) in pending where data != existing {
            let staging = directory.appendingPathComponent(".roarkt-patch-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            try data.write(to: staging, options: .withoutOverwriting)
            if existing == nil {
                // Publish complete bytes atomically without clobbering a user file created since validation.
                try FileManager.default.linkItem(at: staging, to: url)
            } else {
                let values = try FileManager.default.attributesOfItem(atPath: url.path)
                guard try Data(contentsOf: url) == existing, values[.type] as? FileAttributeType == .typeRegular else {
                    return Result(changed: changed, conflicts: [url.lastPathComponent])
                }
                // librime compares integer-second mtimes. Rapid preference toggles must still invalidate its build.
                let previous = floor((values[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
                let next = max(floor(Date().timeIntervalSince1970), previous + 1)
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: next)], ofItemAtPath: staging.path)
                guard rename(staging.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            }
            changed = true
        }
        return Result(changed: changed, conflicts: [])
    }
}
