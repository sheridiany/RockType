import Foundation
import RoarkTCore

/// Bounded, ephemeral ASR vocabulary. Never reads learning databases or persists personal terms.
enum VoiceContextVocabulary {
    static let maximumBytes = 4096
    static let technicalNames = ["SwiftUI", "Xcode", "GitHub", "OpenAI", "Qwen", "MLX", "JSON", "API", "SDK", "TypeScript", "Docker", "Kubernetes"]

    static func context(factory: String, personal: [String]) -> String {
        var groups = [[String]]()
        var section = [String]()
        var body = false
        for line in factory.components(separatedBy: .newlines) {
            if line == "..." { body = true; continue }
            guard body else { continue }
            if line.hasPrefix("#") {
                if !section.isEmpty { groups.append(section); section = [] }
            } else if let term = term(from: line) { section.append(term) }
        }
        if !section.isEmpty { groups.append(section) }
        // Personal terms have a small quota, leaving room for all factory domains.
        let personalTerms = personal.flatMap { dictionary in
            dictionary.components(separatedBy: "...\n").last?.components(separatedBy: .newlines).compactMap(term) ?? []
        }
        var candidates = Array(personalTerms.prefix(32)) + technicalNames
        for index in 0..<(groups.map(\.count).max() ?? 0) {
            for group in groups where index < group.count { candidates.append(group[index]) }
        }
        var seen = Set<String>()
        var result = "Technical terms: "
        var count = 0
        for term in candidates where seen.insert(term.lowercased()).inserted {
            let addition = (count == 0 ? "" : ", ") + term
            guard count < 128, result.utf8.count + addition.utf8.count <= maximumBytes else { continue }
            result += addition; count += 1
        }
        return count == 0 ? "" : result
    }

    private static func term(from line: String) -> String? {
        guard !line.hasPrefix("#"), line.contains("\t") else { return nil }
        let value = String(line.prefix { $0 != "\t" })
        guard (2...40).contains(value.count), value.unicodeScalars.allSatisfy({
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || "+-.#".unicodeScalars.contains($0)
        }) else { return nil }
        return value
    }

    static func readDictionary(_ url: URL) -> String {
        // Reject links and non-files; bound reads even if a file grows after inspection.
        guard !Task.isCancelled, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 262_144,
              let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 262_145), data.count <= 262_144 else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func load() -> String {
        let factory = Bundle.main.url(forResource: "VoiceVocabulary", withExtension: "dict.yaml")
            .map(readDictionary) ?? ""
        let root = Identifiers.rimeUserDirectory(home: FileManager.default.homeDirectoryForCurrentUser)
        let personal = ["roarkt_personal.dict.yaml", "roarkt_personal_en.dict.yaml"]
            .map { readDictionary(root.appendingPathComponent($0)) }
        return context(factory: factory, personal: personal)
    }
}
