import Darwin
import Foundation

private final class VoiceChunkProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let limit: Int64
    let update: @Sendable (Int64) -> Void
    init(limit: Int64, update: @escaping @Sendable (Int64) -> Void) {
        self.limit = limit
        self.update = update
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
            downloadTask.cancel() // Do not let a server ignoring Range download an unbounded body.
        } else {
            update(totalBytesWritten)
        }
    }
}

/// Bounded requests, resumable chunks, alternate sources; only a verified file is published.
public struct VoiceFileDownloader: Sendable {
    public enum Event: Sendable {
        case transferring(bytes: Int64, source: String)
        case retrying(source: String, code: Int)
        case verifying
    }
    private let chunkBytes: Int64
    private let timeout: TimeInterval

    public init(chunkBytes: Int64 = 8 * 1024 * 1024, timeout: TimeInterval = 20) {
        self.chunkBytes = max(1, chunkBytes)
        self.timeout = timeout
    }

    public func download(_ file: VoiceModelFile, from sources: [URL], to destination: URL,
                         progress: @escaping @Sendable (Event) -> Void) async throws {
        guard !sources.isEmpty, file.bytes > 0 else { throw URLError(.badURL) }
        let part = destination.appendingPathExtension("part")
        let lock = open(destination.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw CocoaError(.fileLocking) }
        defer { flock(lock, LOCK_UN) }
        let descriptor = open(part.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var offset = Int64(try handle.seekToEnd())
        if offset > file.bytes { try handle.truncate(atOffset: 0); offset = 0 }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = max(timeout * 3, 1)
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var orderedSources = sources
        while offset < file.bytes {
            try Task.checkCancellation()
            let end = min(file.bytes - 1, offset + chunkBytes - 1)
            let received = try await chunk(file, sources: orderedSources, range: offset...end,
                                           session: session, progress: progress)
            orderedSources = [received.source] + sources.filter { $0 != received.source }
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: received.data)
            offset += Int64(received.data.count)
            try handle.synchronize()
        }
        progress(.verifying)
        do {
            let check = Task.detached(priority: .utility) { try file.validate(at: part) }
            try await withTaskCancellationHandler { try await check.value } onCancel: { check.cancel() }
        } catch {
            try? handle.truncate(atOffset: 0)
            throw error
        }
        try Task.checkCancellation()
        guard rename(part.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private func chunk(_ file: VoiceModelFile, sources: [URL], range: ClosedRange<Int64>,
                       session: URLSession, progress: @escaping @Sendable (Event) -> Void) async throws
        -> (data: Data, source: URL) {
        let start = range.lowerBound
        let end = range.upperBound
        var lastError: any Error = URLError(.cannotConnectToHost)
        for attempt in 0..<max(3, sources.count) {
            try Task.checkCancellation()
            let source = sources[attempt % sources.count]
            let host = source.host ?? "download"
            progress(.transferring(bytes: start, source: host))
            do {
                var components = URLComponents(url: source, resolvingAgainstBaseURL: false)!
                components.queryItems = (components.queryItems ?? []) + [
                    URLQueryItem(name: "download", value: "true"),
                    URLQueryItem(name: "roarkt_range", value: "\(start)-\(end)")
                ]
                var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let delegate = VoiceChunkProgress(limit: end - start + 1) { bytes in
                    progress(.transferring(bytes: start + bytes, source: host))
                }
                let (temporary, response) = try await session.download(for: request, delegate: delegate)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                let expectedRange = "bytes \(start)-\(end)/\(file.bytes)"
                let partial = http.statusCode == 206 && http.value(forHTTPHeaderField: "Content-Range") == expectedRange
                let whole = http.statusCode == 200 && start == 0 && end == file.bytes - 1
                guard partial || whole else { throw URLError(.badServerResponse) }
                let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard Int64(size) == end - start + 1 else { throw URLError(.cannotDecodeContentData) }
                return (try Data(contentsOf: temporary), source)
            } catch {
                try Task.checkCancellation()
                lastError = error
                progress(.retrying(source: host, code: (error as NSError).code))
            }
        }
        throw lastError
    }
}
