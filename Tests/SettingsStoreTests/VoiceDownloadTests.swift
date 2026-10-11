import Foundation
import Network
import CryptoKit
import Testing
@testable import RoarkTApp

/// Local Swift HTTP fixture: exercises real URLSession download/range/cancellation behavior.
private final class VoiceDownloadServer: @unchecked Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "voice-download-test")
    let bytes = Data(0..<64)
    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                guard let data else { connection.cancel(); return }
                let request = String(decoding: data, as: UTF8.self)
                let rangeLine = request.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("range:") } ?? ""
                let parts = rangeLine.components(separatedBy: "=").last?.split(separator: "-") ?? []
                guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]), start >= 0, end < 64 else {
                    connection.cancel(); return
                }
                let corrupt = request.contains("/corrupt")
                let wrong = request.contains("/wrong")
                let pause = request.contains("/pause") && start > 0
                let body = corrupt ? Data(repeating: 0, count: end - start + 1) : self.bytes.subdata(in: start..<(end + 1))
                let header = "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(wrong ? 0 : start)-\(end)/64\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                let response = Data(header.utf8) + body
                self.queue.asyncAfter(deadline: .now() + (pause ? 3 : 0)) {
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        listener.start(queue: queue)
    }
    func url(_ path: String) async throws -> URL {
        for _ in 0..<100 {
            if let port = listener.port, port.rawValue > 0 { return URL(string: "http://127.0.0.1:\(port.rawValue)/\(path)")! }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.cannotConnectToHost)
    }
    deinit { listener.cancel() }
}

private func fixtureFile() -> VoiceModelFile {
    .init("model", 64, SHA256.hash(data: Data(0..<64)).map { String(format: "%02x", $0) }.joined())
}
private func temporaryFolder() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

@Test func voiceDownloadResumesAndRejectsCorruptionAndWrongRanges() async throws {
    let server = try VoiceDownloadServer()
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("model")
    let file = fixtureFile()
    let downloader = VoiceFileDownloader(chunkBytes: 16, timeout: 0.3)
    for path in ["corrupt", "wrong"] {
        await #expect(throws: (any Error).self) {
            try await downloader.download(file, from: [try await server.url(path)], to: destination) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        try? FileManager.default.removeItem(at: destination.appendingPathExtension("part"))
    }
    try Data(0..<16).write(to: destination.appendingPathExtension("part"))
    try await downloader.download(file, from: [try await server.url("good")], to: destination) { _ in }
    try file.validate(at: destination)
    #expect(!FileManager.default.fileExists(atPath: destination.appendingPathExtension("part").path))
    try Data(repeating: 0, count: 64).write(to: destination)
    #expect(throws: (any Error).self) { try file.validate(at: destination) }
}

@Test func voiceDownloadCancellationDoesNotPublishAndCanRetry() async throws {
    let server = try VoiceDownloadServer()
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("model")
    let file = fixtureFile()
    let source = try await server.url("pause")
    let task = Task {
        try await VoiceFileDownloader(chunkBytes: 16, timeout: 1).download(file, from: [source], to: destination) { _ in }
    }
    var size = 0
    for _ in 0..<100 {
        size = (try? destination.appendingPathExtension("part").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size >= 16 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(size == 16)
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    try await VoiceFileDownloader(chunkBytes: 16).download(file, from: [try await server.url("good")], to: destination) { _ in }
    try file.validate(at: destination)
}

@MainActor @Test func voiceMissingOrCorruptModelCannotPassLoadGateAndDeletionIsScoped() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VoiceModelStore(root: root)
    let other = root.appendingPathComponent("unrelated")
    try Data([42]).write(to: other)
    await #expect(throws: (any Error).self) { _ = try await store.validate(.small) }
    store.remove(.small)
    #expect(try Data(contentsOf: other) == Data([42]))
}
