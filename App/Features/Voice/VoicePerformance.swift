import Foundation

/// Per-model, memory-only circuit breaker. A slow preview must never build a request backlog.
struct VoicePreviewPolicy {
    static let maximumRTF = 0.8
    private(set) var disabled = Set<VoiceModel>()
    private(set) var realTimeFactors = [VoiceModel: Double]()
    mutating func observe(model: VoiceModel, seconds: Double, audioSeconds: Double) {
        guard seconds.isFinite, audioSeconds > 0 else { disabled.insert(model); return }
        let factor = seconds / audioSeconds
        realTimeFactors[model] = factor
        if factor > Self.maximumRTF { disabled.insert(model) }
    }
    mutating func fail(model: VoiceModel) { disabled.insert(model) }
}

/// Durations only. Resampling runs during capture and is NOT added to release-to-insertion total.
struct VoiceLatency: Sendable {
    var stop = 0.0
    var resamplingDuringCapture = 0.0
    var previewWait = 0.0
    var modelRecovery = 0.0
    var recognition = 0.0
    var cleanup = 0.0
    var polish = 0.0
    var commit = 0.0
    var total = 0.0
}
