import Foundation

public struct AIConnectionTestResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case available, unavailable(AIClientError), unverified }
    public var text: Status = .unverified
    public var streaming: Status = .unverified
    public var image: Status = .unverified
    public var cancellation: Status = .unverified
    public init() {}
}

public struct AIConnectionTester: Sendable {
    private let client: AIClient
    public init(client: AIClient) { self.client = client }

    /// Uses only built-in probe content, never the user's selection or files.
    /// Image stays unverified until the user declares an image-capable model.
    public func run(apiKey: String) async throws -> AIConnectionTestResult {
        var result = AIConnectionTestResult()
        result.text = await probe { _ = try await client.complete(text: "Reply OK.", apiKey: apiKey) }
        try Task.checkCancellation()
        result.streaming = await probe { _ = try await client.stream(text: "Reply OK.", apiKey: apiKey) { _ in } }
        try Task.checkCancellation()
        if client.connection.defaultModelSupportsImages || client.connection.visionModel != nil {
            result.image = await probe {
                _ = try await client.complete(text: "Describe this test image.", apiKey: apiKey,
                                              model: client.connection.visionModel, imageDataURL: Self.testImage)
            }
        }
        try Task.checkCancellation()
        let task = Task {
            try await client.stream(text: "Count slowly from one to one hundred.", apiKey: apiKey) { _ in }
        }
        result.cancellation = await withTaskCancellationHandler {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { task.cancel() }
            task.cancel()
            do { _ = try await task.value; return .unverified }
            catch AIClientError.cancelled { return .available }
            catch let error as AIClientError { return .unavailable(error) }
            catch { return .unavailable(.network) }
        } onCancel: { task.cancel() }
        try Task.checkCancellation()
        return result
    }
    private func probe(_ operation: () async throws -> Void) async -> AIConnectionTestResult.Status {
        do { try await operation(); return .available }
        catch let error as AIClientError { return .unavailable(error) }
        catch { return .unavailable(.network) }
    }
    // A synthetic 1×1 PNG, not a screen capture or user file.
    private static let testImage = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII="
}
