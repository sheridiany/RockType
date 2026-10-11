import Foundation

/// Records which on-disk files last passed the full SHA-256 check. Any change to a file's size,
/// modification date or inode invalidates the record and forces a full re-hash.
enum VoiceModelVerification {
    static let fileName = ".verified.json"
    private struct Stamp: Codable, Equatable { let name: String; let size: Int64; let modified: Double; let inode: UInt64 }

    private static func stamps(model: VoiceModel, in folder: URL) -> [Stamp]? {
        var result: [Stamp] = []
        for file in model.files {
            let url = folder.appendingPathComponent(file.name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.int64Value,
                  let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970,
                  let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
            result.append(Stamp(name: file.name, size: size, modified: modified, inode: inode))
        }
        return result
    }

    static func matches(model: VoiceModel, in folder: URL) -> Bool {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)),
              let recorded = try? JSONDecoder().decode([Stamp].self, from: data),
              let current = stamps(model: model, in: folder) else { return false }
        return recorded == current
    }

    static func record(model: VoiceModel, in folder: URL) {
        guard let current = stamps(model: model, in: folder), let data = try? JSONEncoder().encode(current) else { return }
        try? data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
    }

    static func invalidate(in folder: URL) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(fileName))
    }
}
