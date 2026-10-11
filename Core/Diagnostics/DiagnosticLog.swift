import Foundation
import OSLog

/// A closed vocabulary prevents URLs, authorization values, bodies and filenames entering logs.
public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case settingsLoad, settingsSave, aiConnectionTest, aiRequest, permissionCheck
        case hotkeyRegistration, voiceHoldProbe, onboarding, launchAtLogin, diagnosticExport
    }
    public enum Status: String, Codable, Sendable { case started, succeeded, failed, cancelled, unavailable }
    public enum Failure: String, Codable, Sendable {
        case configuration, network, authentication, model, rateLimit, server, decoding, timeout
        case permission, storage, unknown
        public init(error: any Error) {
            switch error {
            case AIClientError.configuration: self = .configuration
            case AIClientError.unauthorized: self = .authentication
            case AIClientError.modelNotFound: self = .model
            case AIClientError.rateLimited: self = .rateLimit
            case AIClientError.server: self = .server
            case AIClientError.decoding, AIClientError.responseTooLarge: self = .decoding
            case AIClientError.timeout: self = .timeout
            case AIClientError.network: self = .network
            case let error as URLError: self = error.code == .timedOut ? .timeout : .network
            default: self = .unknown
            }
        }
    }
    public let action: Action
    public let status: Status
    public let durationMilliseconds: Int?
    public let failure: Failure?
    public init(action: Action, status: Status, duration: TimeInterval? = nil, failure: Failure? = nil) {
        self.action = action; self.status = status; self.failure = failure
        if let duration, duration.isFinite, duration >= 0 {
            durationMilliseconds = Int(min(duration * 1_000, 86_400_000))
        } else { durationMilliseconds = nil }
    }
}

public actor DiagnosticLog {
    public enum Failure: Error, Equatable { case invalidLimits, entryTooLarge, exportFailed, destinationExists }
    public static let shared = try! DiagnosticLog()
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
            .appendingPathComponent(Identifiers.applicationSupportFolder, isDirectory: true)
    }
    public let directory: URL
    private let maximumBytes: Int
    private let fileCount: Int
    private let logger = Logger(subsystem: Identifiers.appBundleID, category: "diagnostics")
    private struct Record: Codable { let date: Date; let event: DiagnosticEvent }

    public init(directory: URL = defaultDirectory, maximumBytes: Int = 2 * 1024 * 1024, fileCount: Int = 5) throws {
        guard (256...2 * 1024 * 1024).contains(maximumBytes), (1...5).contains(fileCount) else { throw Failure.invalidLimits }
        self.directory = directory; self.maximumBytes = maximumBytes; self.fileCount = fileCount
    }

    public func record(_ event: DiagnosticEvent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(Record(date: Date(), event: event))
        data.append(10)
        guard data.count <= maximumBytes else { throw Failure.entryTooLarge }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let current = file(0)
        if fm.fileExists(atPath: current.path) {
            let attributes = try fm.attributesOfItem(atPath: current.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            if size + data.count > maximumBytes { try rotate() }
        }
        if !fm.fileExists(atPath: current.path) { try Data().write(to: current, options: .withoutOverwriting) }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
        let handle = try FileHandle(forWritingTo: current)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        // Every interpolated string comes from the closed vocabulary above.
        logger.info("action=\(event.action.rawValue, privacy: .public) status=\(event.status.rawValue, privacy: .public) duration_ms=\(event.durationMilliseconds ?? -1, privacy: .public) error=\(event.failure?.rawValue ?? "none", privacy: .public)")
    }

    private func file(_ index: Int) -> URL {
        directory.appendingPathComponent(index == 0 ? "diagnostics.log" : "diagnostics.\(index).log")
    }
    private func rotate() throws {
        let fm = FileManager.default
        let oldest = file(fileCount - 1)
        if fm.fileExists(atPath: oldest.path) { try fm.removeItem(at: oldest) }
        if fileCount > 1 {
            for index in stride(from: fileCount - 2, through: 0, by: -1) {
                let source = file(index)
                if fm.fileExists(atPath: source.path) { try fm.moveItem(at: source, to: file(index + 1)) }
            }
        }
    }

    /// Exports only validated diagnostic records, never arbitrary files from the log directory.
    /// The caller chooses a destination using a save panel. Existing files are not overwritten.
    public func exportZIP(to destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw Failure.destinationExists }
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshot = staging.appendingPathComponent("RoarkT-Diagnostics", isDirectory: true)
        try fm.createDirectory(at: snapshot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        for index in 0..<fileCount {
            let source = file(index)
            guard fm.fileExists(atPath: source.path) else { continue }
            let attributes = try fm.attributesOfItem(atPath: source.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes else { throw Failure.exportFailed }
            let original = try Data(contentsOf: source)
            var sanitized = Data()
            for line in original.split(separator: 10) {
                guard let record = try? decoder.decode(Record.self, from: Data(line)) else { throw Failure.exportFailed }
                // Re-encoding drops unknown fields if a file was externally modified.
                sanitized.append(try encoder.encode(record)); sanitized.append(10)
            }
            let target = snapshot.appendingPathComponent(source.lastPathComponent)
            try sanitized.write(to: target)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        }
        let archive = staging.appendingPathComponent("diagnostics.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", snapshot.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.exportFailed }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.exportFailed }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
        try fm.copyItem(at: archive, to: destination)
    }
}
