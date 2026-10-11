import AVFoundation
import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@Test(.enabled(if: ProcessInfo.processInfo.environment["ROARKT_VOICE_PERFORMANCE"] == "1"))
func syntheticVoicePerformanceBothModels() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let baseline = ProcessInfo.processInfo.environment["ROARKT_VOICE_PERFORMANCE_BASELINE"] == "1"
    let withContext = ProcessInfo.processInfo.environment["ROARKT_VOICE_PERFORMANCE_CONTEXT"] == "1"
    let base = root.appendingPathComponent(".build/r5-ime/performance-" + (baseline ? "before" : withContext ? "context" : "after"))
    let context = withContext ? VoiceContextVocabulary.context(
        factory: try String(contentsOf: root.appendingPathComponent("Rime/roarkt_ai.dict.yaml"), encoding: .utf8), personal: []) : ""
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let wav = base.appendingPathComponent("synthetic.wav")
    let say = Process(); say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-v", "Tingting", "--file-format=WAVE", "--data-format=LEF32@16000", "-o", wav.path,
                     "今天我们一起检查项目进度。请保留标点，完成测试以后再提交代码。"]
    try say.run(); say.waitUntilExit(); try #require(say.terminationStatus == 0)
    let file = try AVAudioFile(forReading: wav)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let values = try #require(buffer.floatChannelData?[0])
    let phrase = Data(bytes: values, count: Int(buffer.frameLength) * 4) + Data(repeating: 0, count: 16_000)
    let tailWav = base.appendingPathComponent("synthetic-tail.wav")
    let tailSay = Process(); tailSay.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    tailSay.arguments = ["-v", "Tingting", "--file-format=WAVE", "--data-format=LEF32@16000", "-o", tailWav.path,
                         "最后一句，香蕉苹果葡萄。"]
    try tailSay.run(); tailSay.waitUntilExit(); try #require(tailSay.terminationStatus == 0)
    let tailFile = try AVAudioFile(forReading: tailWav)
    let tailBuffer = try #require(AVAudioPCMBuffer(pcmFormat: tailFile.processingFormat, frameCapacity: AVAudioFrameCount(tailFile.length)))
    try tailFile.read(into: tailBuffer)
    let tailValues = try #require(tailBuffer.floatChannelData?[0])
    let tailAudio = Data(repeating: 0, count: 32_000) + Data(bytes: tailValues, count: Int(tailBuffer.frameLength) * 4)
    for model in VoiceModel.allCases {
        let output = base.appendingPathComponent(model.rawValue)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try context.write(to: output.appendingPathComponent("context.txt"), atomically: true, encoding: .utf8)
        let modelURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/" + Identifiers.applicationSupportFolder + "/VoiceModels/" + model.rawValue)
        for part in model.files { try part.validate(at: modelURL.appendingPathComponent(part.name)) }
        let durations = baseline ? [6, 6, 6, 28, 55] : [6, 6, 6, 28, 55, 75, 180, 3, 3, 3]
        var names = [String]()
        for (index, seconds) in durations.enumerated() {
            var data = Data()
            while data.count < seconds * 64_000 { data.append(phrase) }
            data = Data(data.prefix(seconds * 64_000))
            let name = "synthetic-\(seconds)s-\(seconds >= 75 ? "tail-" : "")\(index).pcm"
            if seconds >= 75 { data.replaceSubrange((data.count - tailAudio.count)..<data.count, with: tailAudio) }
            let prior = root.appendingPathComponent(".build/r5-ime/performance-before/" + model.rawValue + "/" + name)
            if !baseline, seconds < 75, FileManager.default.fileExists(atPath: prior.path) { data = try Data(contentsOf: prior) }
            try data.write(to: output.appendingPathComponent(name)); names.append(name)
        }
        if !baseline {
            for (name, data) in [("invalid-too-long.pcm", Data(repeating: 0, count: 181 * 64_000)),
                                 ("invalid-alignment.pcm", Data([1, 2, 3])),
                                 ("invalid-nan.pcm", [Float.nan].withUnsafeBytes { Data($0) })] {
                try data.write(to: output.appendingPathComponent(name)); names.append(name)
            }
        }
        try JSONEncoder().encode(names).write(to: output.appendingPathComponent("performance.json"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [root.appendingPathComponent("Tests/VoiceWorkerSmoke/run.sh").path]
        var environment = ProcessInfo.processInfo.environment
        environment["ROARKT_VOICE_PERFORMANCE_DIR"] = output.path
        environment["ROARKT_VOICE_PERFORMANCE_MODEL"] = modelURL.path
        process.environment = environment
        try process.run(); process.waitUntilExit(); try #require(process.terminationStatus == 0)
        let metrics = try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("performance-metrics.json")))
        let rows = try #require(metrics as? [[String: Any]])
        for row in rows where (row["case"] as? String)?.contains("tail") == true {
            #expect(row["tailDetected"] as? Bool == true, "Long recording must reach its unique final sentence")
        }
        print("Synthetic performance \(model.rawValue): \(metrics)")
    }
}
