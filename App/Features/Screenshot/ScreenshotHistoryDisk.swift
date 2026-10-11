import AppKit
import RoarkTCore

struct ScreenshotHistoryEntry: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let image: CGImage
    let thumbnail: CGImage
    var text: String
    var recognized = false
    static func cachedText(_ text: String) -> String { String(decoding: text.utf8.prefix(65_536), as: UTF8.self) }
    var bytes: Int { image.bytesPerRow * image.height + thumbnail.bytesPerRow * thumbnail.height + text.utf8.count }
    init(id: UUID = UUID(), date: Date, image: CGImage, text: String = "") {
        self.id = id; self.date = date; self.image = image; self.text = Self.cachedText(text)
        let scale = min(1, 240 / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        thumbnail = context?.makeImage() ?? image
    }
}

/// Serial, bounded archive. UUID filenames only; never follows links outside its own directory.
actor ScreenshotHistoryDisk {
    struct Metadata: Codable { let id: UUID; let date: Date; let text: String; var recognized: Bool? = nil }
    private let folder: URL
    private var revision = 0
    init(folder: URL = Identifiers.screenshotHistoryDirectory()) { self.folder = folder }
    private func validate() throws {
        var path = folder
        while path.path != "/" {
            // URL resource values can be cached across calls after the directory is replaced.
            let type = (try? FileManager.default.attributesOfItem(atPath: path.path)[.type]) as? FileAttributeType
            if type == .typeSymbolicLink { throw CocoaError(.fileWriteNoPermission) }
            path.deleteLastPathComponent()
        }
    }
    private func regular(_ url: URL, maximum: Int) throws -> Bool {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        return values[.type] as? FileAttributeType == .typeRegular && (values[.size] as? Int ?? Int.max) <= maximum
    }
    func load(allowed: @MainActor @Sendable () -> Bool) async throws -> [ScreenshotHistoryEntry] {
        try Task.checkCancellation()
        guard await allowed() else { throw CancellationError() }
        try validate()
        let manifest = folder.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        guard try regular(manifest, maximum: 96 * 1024 * 1024) else { throw CocoaError(.fileReadCorruptFile) }
        let metadata = try JSONDecoder().decode([Metadata].self, from: Data(contentsOf: manifest))
        guard metadata.count <= 200 else { throw CocoaError(.fileReadCorruptFile) }
        var entries: [ScreenshotHistoryEntry] = [], bytes = 0, seen = Set<UUID>()
        for item in metadata.sorted(by: { $0.date > $1.date }).prefix(200) {
            try Task.checkCancellation()
            guard await allowed() else { throw CancellationError() }
            try validate()
            guard seen.insert(item.id).inserted else { continue }
            let url = folder.appendingPathComponent(item.id.uuidString + ".png")
            guard (try? regular(url, maximum: 40 * 1024 * 1024)) == true,
                  let image = try? ScreenshotImageImport.decode(Data(contentsOf: url)) else { continue }
            var entry = ScreenshotHistoryEntry(id: item.id, date: item.date, image: image, text: item.text)
            entry.recognized = item.recognized ?? !entry.text.isEmpty
            guard bytes + entry.bytes <= 256 * 1024 * 1024 else { continue }
            entries.append(entry); bytes += entry.bytes
        }
        return entries
    }
    func write(_ entries: [ScreenshotHistoryEntry], revision next: Int, enabled: Bool,
               allowed: @MainActor @Sendable () -> Bool) async throws {
        guard next >= revision else { return }; revision = next
        try Task.checkCancellation(); try validate()
        let fm = FileManager.default
        if !enabled || entries.isEmpty {
            if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
            return
        }
        guard await allowed(), revision == next else { throw CancellationError() }
        try Task.checkCancellation(); try validate()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var metadata: [Metadata] = []
        for entry in entries.prefix(200) {
            guard await allowed(), revision == next else { throw CancellationError() }
            try Task.checkCancellation(); try validate()
            let url = folder.appendingPathComponent(entry.id.uuidString + ".png")
            if !fm.fileExists(atPath: url.path) {
                guard let data = NSBitmapImageRep(cgImage: entry.image).representation(using: .png, properties: [:]),
                      data.count <= 40 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
                guard await allowed(), revision == next else { throw CancellationError() }
                try Task.checkCancellation(); try validate()
                try data.write(to: url, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } else if try !regular(url, maximum: 40 * 1024 * 1024) { throw CocoaError(.fileWriteNoPermission) }
            metadata.append(.init(id: entry.id, date: entry.date, text: entry.text, recognized: entry.recognized))
        }
        guard await allowed(), revision == next else { throw CancellationError() }
        try Task.checkCancellation(); try validate()
        let index = folder.appendingPathComponent("index.json")
        if fm.fileExists(atPath: index.path), try !regular(index, maximum: 96 * 1024 * 1024) { throw CocoaError(.fileWriteNoPermission) }
        try JSONEncoder().encode(metadata).write(to: index, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: index.path)
        let keep = Set(metadata.map { $0.id.uuidString + ".png" })
        for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            if url.pathExtension == "png", UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil, !keep.contains(url.lastPathComponent) {
                try fm.removeItem(at: url)
            }
        }
    }
}
