import Foundation
import Observation
import RoarkTCore

/// Runtime-only storage. No Codable conformance or disk backend by design.
@MainActor @Observable
public final class InMemoryRecentResults: RecentResults {
    public private(set) var results: [OperationResult] = []
    public init() {}
    public func start() {}
    public func stop() { clear() }
    public func add(_ result: OperationResult) {
        results.removeAll { $0.id == result.id }
        results.insert(result, at: 0)
        if results.count > 10 { results.removeLast(results.count - 10) }
    }
    public func clear() { results.removeAll() }
}
