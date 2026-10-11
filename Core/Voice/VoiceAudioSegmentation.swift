import Foundation

/// Bounded PCM policy shared by capture and the isolated model worker (16 kHz mono Float32).
public enum VoiceAudioSegmentation {
    public static let sampleRate = 16_000
    public static let maximumSeconds = 180
    public static let segmentSeconds = 28
    public static let previewSeconds = 3
    public static let maximumBytes = maximumSeconds * sampleRate * MemoryLayout<Float>.size

    /// Disjoint, exhaustive ranges. Search only BEFORE the hard limit, unlike the SDK's ±5s search.
    public static func ranges(in samples: [Float]) -> [Range<Int>] {
        var result = [Range<Int>]()
        var start = 0
        let frame = sampleRate / 50 // 20 ms
        while start < samples.count {
            let limit = min(start + segmentSeconds * sampleRate, samples.count)
            var cut = limit
            if limit < samples.count {
                let search = max(start + sampleRate, limit - 5 * sampleRate)
                var quietStart: Int?
                for offset in stride(from: search, through: limit - frame, by: frame) {
                    var energy: Float = 0
                    for value in samples[offset..<(offset + frame)] { energy += value * value }
                    if energy / Float(frame) < 0.000004 { // RMS < 0.002
                        if quietStart == nil { quietStart = offset }
                        if let quietStart, offset + frame - quietStart >= sampleRate * 3 / 10 {
                            cut = (quietStart + offset + frame) / 2
                        }
                    } else { quietStart = nil }
                }
            }
            result.append(start..<cut)
            start = cut
        }
        return result
    }

    /// No overlapping audio, so never deduplicate legitimate repeated speech or invent punctuation.
    public static func join(_ texts: [String]) -> String {
        texts.reduce(into: "") { result, text in
            let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !next.isEmpty else { return }
            if let last = result.unicodeScalars.last, let first = next.unicodeScalars.first,
               last.isASCII, first.isASCII, !CharacterSet.punctuationCharacters.contains(first) {
                result += " "
            }
            result += next
        }
    }
}
