import Foundation
import RoarkTCore
import Testing
@testable import RoarkTTranslationService

@MainActor private final class ImmediateCandidateBackend: DynamicTextTranslating {
    func translate(_ text: String, direction: DynamicTranslationDirection) async throws -> String { "synthetic result" }
}

/// Measures the real coordinator with an immediate local backend; excludes XPC/Apple/network latency.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ROARKT_MEASURE_DEBOUNCE"] == "1")) @MainActor
func candidateServiceDispatchLatency() async throws {
    let coordinator = TranslationCoordinator(backend: ImmediateCandidateBackend())
    let request = try CandidateTranslationRequest(rawInput: "ceshi", sourceText: "测试", identity: "0:5:0", scope: .whole)
    let clock = ContinuousClock()
    var milliseconds: [Double] = []
    for _ in 0..<20 {
        let start = clock.now
        let code: Int? = await withCheckedContinuation { continuation in
            coordinator.translate(connectionID: UUID(), sessionID: UUID().uuidString, generation: 1, request: request) {
                _, _, _, _, error in continuation.resume(returning: error?.code)
            }
        }
        #expect(code == nil)
        let elapsed = start.duration(to: clock.now).components
        milliseconds.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
    }
    milliseconds.sort()
    print("candidate-service-ms n=20 median=\(milliseconds[10]) p95=\(milliseconds[18])")
}
