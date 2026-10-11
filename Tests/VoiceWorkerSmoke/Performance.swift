import Foundation

/// Synthetic fixtures only; emits timings/counts, never transcripts.
final class VoicePerformanceEvaluation: @unchecked Sendable {
    private let proxy: VoiceWorkerProtocol
    private let directory: URL
    private let cases: [String]
    private let context: String
    private var index = 0
    private var metrics = [[String: Any]]()
    init(proxy: VoiceWorkerProtocol, directory: URL) throws {
        self.proxy = proxy; self.directory = directory
        let contextFile = directory.appendingPathComponent("context.txt")
        context = FileManager.default.fileExists(atPath: contextFile.path)
            ? try String(contentsOf: contextFile, encoding: .utf8) : ""
        guard context.utf8.count <= 4096 else { throw CocoaError(.fileReadCorruptFile) }
        cases = try JSONDecoder().decode([String].self, from: Data(contentsOf: directory.appendingPathComponent("performance.json")))
        guard !cases.isEmpty, cases.count <= 20 else { throw CocoaError(.fileReadCorruptFile) }
    }
    func next() {
        guard index < cases.count else {
            do {
                try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("performance-metrics.json"))
                finish(0)
            } catch { finish(1) }
        }
        let name = cases[index]
        guard !name.contains("/"), name.hasSuffix(".pcm"),
              let audio = try? Data(contentsOf: directory.appendingPathComponent(name)) else { finish(1) }
        let start = ProcessInfo.processInfo.systemUptime
        proxy.transcribe(audio: audio, context: context) { [self] text in
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let seconds = Double(audio.count) / 64_000
            if name.hasPrefix("invalid-") {
                guard text == nil else { finish(1) }
                metrics.append(["case": name, "rejected": true])
                index += 1; next(); return
            }
            guard let text, !text.isEmpty else { finish(1) }
            let tail = String(text.filter { $0.isLetter || $0.isNumber }).contains("香蕉苹果葡萄")
            metrics.append(["case": name, "audioSeconds": seconds, "recognitionSeconds": elapsed,
                            "rtf": elapsed / seconds, "characters": text.count,
                            "punctuation": text.filter { $0.isPunctuation }.count, "tailDetected": tail, "contextBytes": context.utf8.count])
            index += 1
            next()
        }
    }
}
