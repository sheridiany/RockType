import CoreGraphics

struct ScrollStitchLimits: Sendable {
    var maxHeight = 30_000
    var maxBytes = 128 * 1024 * 1024
    var maxFrames = 32
}
struct ScrollStitchUpdate: Sendable {
    enum Outcome: Sendable, Equatable { case started, added, unchanged, ambiguous, gap, reversed, limit }
    let outcome: Outcome
    let height: Int
    /// Bounded thumbnail, never the full composite on each sample.
    let thumbnail: CGImage?
}
protocol ScrollStitching: Sendable {
    func append(_ image: CGImage) async throws -> ScrollStitchUpdate
    func finish() async throws -> CGImage
    func reset() async
}
