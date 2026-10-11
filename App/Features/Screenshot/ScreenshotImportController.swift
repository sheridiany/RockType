import AppKit
import UniformTypeIdentifiers

/// Async import lifetime is separate from capture windows and output actions.
@MainActor final class ScreenshotImportController {
    private let allowed: () -> Bool
    private let decode: @Sendable (Data) throws -> CGImage
    private let loadBatch: @Sendable ([URL]) throws -> [CGImage]
    var onImage: (CGImage, String, Bool) -> Void = { _, _, _ in }
    var onBatch: ([CGImage]) -> Void = { _ in }
    var onNotice: (String) -> Void = { _ in }
    private var task: Task<Void, Never>?
    private var progress: Progress?
    private var generation = 0

    init(allowed: @escaping () -> Bool, decode: @escaping @Sendable (Data) throws -> CGImage = ScreenshotImageImport.decode,
         loadBatch: @escaping @Sendable ([URL]) throws -> [CGImage] = ScreenshotBatch.load) {
        self.allowed = allowed; self.decode = decode; self.loadBatch = loadBatch
    }
    func cancel() {
        generation += 1; task?.cancel(); task = nil; progress?.cancel(); progress = nil
    }
    func load(_ data: Data, origin: String, recognize: Bool = false) {
        cancel()
        guard allowed() else { return }
        run(origin: origin, current: generation, recognize: recognize) { data }
    }
    func load(_ provider: NSItemProvider, type: String) {
        cancel()
        guard allowed() else { return }
        let current = generation
        progress = provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
            Task { @MainActor [weak self] in
                guard let self, current == self.generation, self.allowed() else { return }
                self.progress = nil
                guard let data else { self.onNotice("无法读取拖入的图片。"); return }
                if type == UTType.fileURL.identifier {
                    guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                        self.onNotice("请拖入本机图片文件。"); return
                    }
                    self.run(origin: "拖入图片", current: current) { try ScreenshotImageImport.read(url) }
                } else { self.run(origin: "拖入图片", current: current) { data } }
            }
        }
    }
    func load(_ urls: [URL]) {
        cancel()
        guard allowed() else { return }
        let current = generation, loadBatch = loadBatch
        task = Task { [weak self] in
            do {
                let worker = Task.detached { try loadBatch(urls) }
                let images = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, !Task.isCancelled, current == self.generation, self.allowed() else { return }
                self.task = nil; self.onBatch(images)
            } catch {
                guard let self, !Task.isCancelled, current == self.generation, self.allowed() else { return }
                self.task = nil
                self.onNotice("无法打开这批图片。请选择最多 10 张 PNG、JPEG 或 TIFF，总像素内存不超过 128 MB。")
            }
        }
    }
    private func run(origin: String, current: Int, recognize: Bool = false, read: @escaping @Sendable () throws -> Data) {
        let decode = decode
        task = Task { [weak self] in
            do {
                let worker = Task.detached { try decode(read()) }
                let image = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, !Task.isCancelled, current == self.generation, self.allowed() else { return }
                self.task = nil; self.onImage(image, origin, recognize)
            } catch {
                guard let self, !Task.isCancelled, current == self.generation, self.allowed() else { return }
                self.task = nil
                self.onNotice(error as? ScreenshotImageImport.Failure == .tooLarge
                    ? "图片过大：支持最大 40 MB、6400 万像素，请缩小后重试。" : "图片无法打开，请使用 PNG、JPEG 或 TIFF 图片。")
            }
        }
    }
    isolated deinit { task?.cancel(); progress?.cancel() }
}
