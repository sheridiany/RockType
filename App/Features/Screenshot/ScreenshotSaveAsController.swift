import AppKit
import RoarkTCore

/// Owns a single save dialog, its image, and its cancellation boundary.
@MainActor final class ScreenshotSaveAsController {
    enum Outcome { case saved, cancelled, failed }
    typealias Choose = @MainActor (_ format: ScreenshotSettings.Format, _ reply: @escaping (URL?) -> Void) -> (() -> Void)
    private let allowed: () -> Bool
    private let choose: Choose
    private let write: (Data, URL) throws -> Void
    private var dismiss: (() -> Void)?
    private var image: CGImage?
    private var completion: ((Outcome) -> Void)?
    private var generation = 0
    var isPresenting: Bool { image != nil }

    init(allowed: @escaping () -> Bool, choose: @escaping Choose = ScreenshotSaveAsController.chooseURL,
         write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.allowed = allowed; self.choose = choose; self.write = write
    }
    static func chooseURL(format: ScreenshotSettings.Format, reply: @escaping (URL?) -> Void) -> (() -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .png ? [.png] : [.jpeg]
        panel.nameFieldStringValue = format == .png ? "截图.png" : "截图.jpg"
        panel.begin { response in reply(response == .OK ? panel.url : nil) }
        return { panel.cancel(nil) }
    }
    func present(image: CGImage, format: ScreenshotSettings.Format, completion: @escaping (Outcome) -> Void) {
        guard !isPresenting else { return }
        guard allowed() else { completion(.cancelled); return }
        generation += 1
        let current = generation
        self.image = image; self.completion = completion
        let cancelDialog = choose(format) { [weak self] url in
            guard let self, current == self.generation, let image = self.image else { return }
            guard self.allowed(), let url else { self.finish(.cancelled); return }
            guard url.isFileURL, let data = ScreenshotExport.encode(image, jpeg: format == .jpeg), self.allowed() else {
                self.finish(.failed); return
            }
            do { try self.write(data, url); self.finish(.saved) }
            catch { self.finish(.failed) }
        }
        // Injected dialogs may complete synchronously; never retain a stale cancellation closure.
        if current == generation, isPresenting { dismiss = cancelDialog }
    }
    func cancel() {
        let dismiss = dismiss
        finish(.cancelled)
        dismiss?()
    }
    private func finish(_ outcome: Outcome) {
        generation += 1
        let callback = completion
        image = nil; completion = nil; dismiss = nil
        callback?(outcome)
    }
}
