import AppKit
import RoarkTCore
import RoarkTPlatform

/// Explicit output only. No logging of images or paths. Call after compositing annotations.
@MainActor final class ScreenshotOutput {
    static let shared = ScreenshotOutput()
    enum Failure: Error { case protectedInput, invalidDirectory, encoding, nameExhausted }
    private let settings: () -> ScreenshotSettings
    private let allowed: () -> Bool
    private let now: () -> Date
    private let pasteboard: NSPasteboard

    init(settings: @escaping () -> ScreenshotSettings = { SettingsStore.shared.settings.screenshot },
         allowed: @escaping () -> Bool = { ScreenCapture.isReadable },
         now: @escaping () -> Date = Date.init, pasteboard: NSPasteboard = .general) {
        self.settings = settings; self.allowed = allowed; self.now = now; self.pasteboard = pasteboard
    }

    static func directory(_ settings: ScreenshotSettings, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        guard let path = settings.saveDirectory else {
            return home.appendingPathComponent("Pictures/RockType", isDirectory: true)
        }
        guard path.hasPrefix("/"), !path.contains("\0") else { throw Failure.invalidDirectory }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func filename(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "RockType-\(formatter.string(from: date)).png"
    }

    func save(_ image: CGImage) throws -> URL {
        guard allowed() else { throw Failure.protectedInput }
        let folder = try Self.directory(settings())
        let data = try Self.png(image)
        guard allowed() else { throw Failure.protectedInput }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let base = Self.filename(at: now())
        for index in 0..<1000 {
            let name = index == 0 ? base : String(base.dropLast(4)) + "-\(index + 1).png"
            let url = folder.appendingPathComponent(name)
            guard allowed() else { throw Failure.protectedInput }
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists { continue }
        }
        throw Failure.nameExhausted
    }

    /// Plain absolute path, without shell escaping; consumers may be editors or terminals.
    func copyPath(_ url: URL) throws {
        guard allowed() else { throw Failure.protectedInput }
        guard url.isFileURL else { throw Failure.invalidDirectory }
        pasteboard.clearContents()
        guard pasteboard.setString(url.path, forType: .string) else { throw PlatformReadError.writeFailed }
    }

    func copyImage(_ image: CGImage) throws {
        guard allowed() else { throw Failure.protectedInput }
        let data = try Self.png(image)
        guard allowed() else { throw Failure.protectedInput }
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else { throw PlatformReadError.writeFailed }
    }

    func copyColor(_ hex: String) throws {
        guard allowed() else { throw Failure.protectedInput }
        pasteboard.clearContents()
        guard pasteboard.setString(hex, forType: .string) else { throw PlatformReadError.writeFailed }
    }

    private static func png(_ image: CGImage) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Failure.encoding
        }
        return data
    }
}
