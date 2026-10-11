import CryptoKit
import Foundation

public enum VoiceModel: String, CaseIterable, Identifiable, Sendable {
    case small = "qwen3-asr-0.6b-8bit"
    case large = "qwen3-asr-1.7b-8bit"

    public var id: String { rawValue }
    public var title: String { self == .small ? "0.6B · 快速 · 约 1.01 GB" : "1.7B · 增强 · 约 2.46 GB" }
    public var repository: String { "mlx-community/Qwen3-ASR-\(self == .small ? "0.6B" : "1.7B")-8bit" }
    public var revision: String {
        self == .small ? "89e96d92ba34aca20b3e29fb10cc284097d1219f" : "a8379a2e2f9e313c9292cdf1af4055ab56d50d55"
    }
    public var files: [VoiceModelFile] {
        [
            .init("config.json", self == .small ? 7187 : 7188, self == .small
                  ? "5d104a945fed08728ab010f12bf3ce5ab4d0794bba276d81bff5bd83ae9d2be0"
                  : "1b76b3b6c655fc54595da025f7a96474ad9fa86363303fbdd61a7d8483ccfaf7"),
            .init("tokenizer_config.json", 12487, "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"),
            .init("vocab.json", 2776833, "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
            .init("merges.txt", 1671853, "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
            .init("model.safetensors", self == .small ? 1_006_229_426 : 2_463_307_541, self == .small
                  ? "b5bfe4abc1b4c6e58b633096682ec2b6297298add1527119936107d211adf0e8"
                  : "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c")
        ]
    }
}

public struct VoiceModelFile: Sendable {
    public let name: String
    public let bytes: Int64
    public let sha256: String

    public init(_ name: String, _ bytes: Int64, _ sha256: String) {
        self.name = name
        self.bytes = bytes
        self.sha256 = sha256
    }

    public func validate(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == bytes else { throw CocoaError(.fileReadCorruptFile) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 4 * 1024 * 1024), !block.isEmpty {
            try Task.checkCancellation()
            hash.update(data: block)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
