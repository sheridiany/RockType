import Foundation

struct VoiceAccuracySample: Codable, Sendable {
    let pcm: String
    let expected: String
    let terms: [String]
}

// One outstanding XPC call at a time. Only generated fixture audio is accepted by this test host.
final class VoiceAccuracyEvaluation: @unchecked Sendable {
    private let proxy: VoiceWorkerProtocol
    private let directory: URL
    private let samples: [VoiceAccuracySample]
    private let context: String
    private var index = 0
    private var errors = [0, 0]
    private var hits = [0, 0]
    private var characters = 0
    private var termCount = 0

    init(proxy: VoiceWorkerProtocol, directory: URL) throws {
        self.proxy = proxy; self.directory = directory
        samples = try JSONDecoder().decode([VoiceAccuracySample].self, from: Data(contentsOf: directory.appendingPathComponent("samples.json")))
        context = try String(contentsOf: directory.appendingPathComponent("context.txt"), encoding: .utf8)
        guard !samples.isEmpty, samples.count <= 10, context.utf8.count <= 4096 else { throw CocoaError(.fileReadCorruptFile) }
        characters = samples.reduce(0) { $0 + Self.normalized($1.expected).count }
        termCount = samples.reduce(0) { $0 + $1.terms.count }
    }

    func next() {
        guard index < samples.count * 2 else {
            let metrics: [String: Int] = ["samples": samples.count, "characters": characters, "terms": termCount,
                "baselineErrors": errors[0], "contextErrors": errors[1], "baselineTermHits": hits[0], "contextTermHits": hits[1]]
            do {
                try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys, .prettyPrinted])
                    .write(to: directory.appendingPathComponent("metrics.json"))
                print("Synthetic voice evaluation completed: \(samples.count) samples")
                finish(0)
            } catch { finish(1) }
        }
        let sample = samples[index / 2], variant = index % 2
        guard !sample.pcm.contains("/"), sample.pcm.hasSuffix(".pcm"),
              let audio = try? Data(contentsOf: directory.appendingPathComponent(sample.pcm)) else { finish(1) }
        proxy.transcribe(audio: audio, context: variant == 0 ? "" : context) { [self] text in
            guard let text else { finish(1) }
            let normalized = Self.normalized(text)
            errors[variant] += Self.distance(Self.normalized(sample.expected), normalized)
            hits[variant] += sample.terms.filter { String(normalized).contains(String(Self.normalized($0))) }.count
            index += 1
            next()
        }
    }

    private static func normalized(_ text: String) -> [Character] {
        Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
    private static func distance(_ expected: [Character], _ actual: [Character]) -> Int {
        var previous = Array(0...actual.count)
        for (i, e) in expected.enumerated() {
            var current = [i + 1]
            for (j, a) in actual.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (e == a ? 0 : 1)))
            }
            previous = current
        }
        return previous.last!
    }
}
