import Foundation

public struct OperationTurn: Equatable, Sendable {
    public let question: String
    public let answer: String
    public init(question: String, answer: String) { self.question = question; self.answer = answer }
}

/// Only completed turns belong in this session. New operations get a new session ID.
public struct OperationSession: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let snapshot: ContentSnapshot
    public let turns: [OperationTurn]
    public init(id: UUID = UUID(), snapshot: ContentSnapshot, turns: [OperationTurn] = []) {
        self.id = id; self.snapshot = snapshot; self.turns = turns
    }
}

public struct OperationRequest: Sendable {
    public let session: OperationSession
    public let template: OperationTemplate
    public let settings: AppSettings
    public let question: String?
    /// Explicit model input budget in UTF-8 bytes (conservative token upper bound).
    /// The caller supplies the selected model's supported input budget, after output reserve.
    public let maximumInputBytes: Int
    public init(session: OperationSession, template: OperationTemplate, settings: AppSettings,
                question: String? = nil, maximumInputBytes: Int = 16_384) {
        self.session = session; self.template = template; self.settings = settings
        self.question = question; self.maximumInputBytes = maximumInputBytes
    }
}

public enum OperationFailure: Error, Equatable, Sendable {
    case emptyInput, inputTooLong(limit: Int), unsupportedInput, protectedInput
    case unavailable, invalidSearchURL
    case ai(AIClientError)
}

public struct OperationResult: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let session: OperationSession
    public let templateID: String
    public let text: String
    /// Actual engine or model used, suitable for presentation.
    public let engine: String
    public let completedAt: Date
    public init(id: UUID = UUID(), session: OperationSession, templateID: String, text: String,
                engine: String, completedAt: Date = Date()) {
        self.id = id; self.session = session; self.templateID = templateID; self.text = text
        self.engine = engine; self.completedAt = completedAt
    }
}

public enum OperationEvent: Equatable, Sendable {
    case started(generation: UInt64)
    case engine(String)
    case delta(String)
    case completed(OperationResult)
    case failed(OperationFailure)
    case cancelled
}

/// One runner per result window. Starting again cancels and finishes the previous stream.
/// All terminal events finish the stream; no deltas follow cancellation or supersession.
@MainActor
public protocol OperationRunner: AnyObject {
    func start()
    func stop()
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent>
    func cancel()
}

@MainActor
public protocol RecentResults: AnyObject {
    var results: [OperationResult] { get }
    func start()
    func stop()
    func add(_ result: OperationResult)
    func clear()
}

/// UI development stub. It never reads credentials or makes network requests.
@MainActor
public final class StubOperationRunner: OperationRunner {
    public var events: [OperationEvent]
    private var generation: UInt64 = 0
    public init(events: [OperationEvent] = [.delta("示例结果")]) { self.events = events }
    public func start() {}
    public func stop() { cancel() }
    public func cancel() {}
    public func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        generation &+= 1
        let events = self.events
        let generation = self.generation
        return AsyncStream { continuation in
            continuation.yield(.started(generation: generation))
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}
