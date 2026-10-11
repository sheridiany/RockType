import AVFoundation
import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

/// Explicit opt-in: synthesizes fixed public test sentences, never records the microphone.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ROARKT_VOICE_EVALUATION"] == "1"))
func syntheticMixedLanguageVoiceAccuracy() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent(".build/r1c-ime/voice-accuracy")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let samples: [(String, [String])] = [
        ("请使用 SwiftUI 开发界面，并在 GitHub 提交代码。", ["SwiftUI", "GitHub"]),
        ("使用 JSON 调用 API，然后检查异步回调。", ["JSON", "API", "异步回调"]),
        ("请在 Xcode 检查线程调度和编译错误。", ["Xcode", "线程调度", "编译错误"]),
        // Additional cases held out while choosing the context budget.
        ("请把 Docker 镜像部署到 Kubernetes。", ["Docker", "Kubernetes"]),
        ("这个 API 返回 JSON，请检查字段类型。", ["API", "JSON"]),
        ("使用 Xcode 编译项目，然后提交到 GitHub。", ["Xcode", "GitHub"])
    ]
    var manifest = [[String: Any]]()
    for (index, sample) in samples.enumerated() {
        let wav = output.appendingPathComponent("sample-\(index).wav")
        let synth = Process()
        synth.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        synth.arguments = ["-v", "Tingting", "--file-format=WAVE", "--data-format=LEF32@16000", "-o", wav.path, sample.0]
        try synth.run(); synth.waitUntilExit()
        try #require(synth.terminationStatus == 0)
        let file = try AVAudioFile(forReading: wav)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        try #require(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
        let channel = try #require(buffer.floatChannelData?[0])
        let pcm = "sample-\(index).pcm"
        try Data(bytes: channel, count: Int(buffer.frameLength) * 4).write(to: output.appendingPathComponent(pcm))
        manifest.append(["pcm": pcm, "expected": sample.0, "terms": sample.1])
    }
    try JSONSerialization.data(withJSONObject: manifest).write(to: output.appendingPathComponent("samples.json"))
    let vocabulary = try String(contentsOf: root.appendingPathComponent("Rime/roarkt_ai.dict.yaml"), encoding: .utf8)
    try VoiceContextVocabulary.context(factory: vocabulary, personal: [])
        .write(to: output.appendingPathComponent("context.txt"), atomically: true, encoding: .utf8)
    let model = VoiceModelStoreForEvaluation.smallModelURL
    try #require(FileManager.default.fileExists(atPath: model.appendingPathComponent("model.safetensors").path), "Evaluation requires an already downloaded model; never downloads implicitly")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [root.appendingPathComponent("Tests/VoiceWorkerSmoke/run.sh").path]
    var environment = ProcessInfo.processInfo.environment
    environment["ROARKT_VOICE_EVALUATION_DIR"] = output.path
    environment["ROARKT_VOICE_EVALUATION_MODEL"] = model.path
    process.environment = environment
    try process.run(); process.waitUntilExit()
    try #require(process.terminationStatus == 0)
    let metrics = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("metrics.json"))) as? [String: Int])
    #expect(metrics["samples"] == samples.count)
    #expect(metrics["terms"] == 14)
    // Quality measurements are reported, not disguised as a guaranteed improvement assertion.
    print("Synthetic ASR metrics: \(metrics)")
}

private enum VoiceModelStoreForEvaluation {
    static var smallModelURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/" + Identifiers.applicationSupportFolder + "/VoiceModels/" + VoiceModel.small.rawValue)
    }
}
