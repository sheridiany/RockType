import AppKit
import Observation
import RoarkTPlatform

@MainActor protocol ScrollFrameSource: AnyObject {
    func next() async throws -> CGImage
    func stop()
}
extension ScrollRegionCapture: ScrollFrameSource {}

/// Serial capture -> matching -> thumbnail. No overlapping samples or unbounded frame queue.
@MainActor @Observable final class ScrollCaptureController {
    enum Phase { case idle, preparing, capturing, limited, finishing, closed }
    private(set) var phase: Phase = .idle
    private(set) var thumbnail: CGImage?
    private(set) var height = 0
    private(set) var message = "准备长截图…"
    var canFinish: Bool { height > 0 && (phase == .capturing || phase == .limited) }
    var onComplete: (CGImage) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onFailure: (String) -> Void = { _ in }
    @ObservationIgnored private let allowed: () -> Bool
    @ObservationIgnored private let prepare: () async throws -> any ScrollFrameSource
    @ObservationIgnored private let stitcher: any ScrollStitching
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var source: (any ScrollFrameSource)?
    @ObservationIgnored private var sampling: Task<Void, Never>?
    @ObservationIgnored private var finishing: Task<Void, Never>?
    @ObservationIgnored private var protection: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    init(allowed: @escaping () -> Bool, prepare: @escaping () async throws -> any ScrollFrameSource,
         stitcher: any ScrollStitching = ScrollStitcher(), interval: Duration = .milliseconds(250)) {
        self.allowed = allowed; self.prepare = prepare; self.stitcher = stitcher; self.interval = interval
    }
    func start() {
        guard phase == .idle else { return }
        guard allowed() else { fail("当前无法安全采集，请检查辅助功能权限与安全输入状态。"); return }
        phase = .preparing; let current = generation
        protection = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, !Task.isCancelled, self.phase != .closed else { return }
                if !self.allowed() { self.fail("安全输入状态发生变化，已取消长截图。"); return }
            }
        }
        sampling = Task { [weak self, prepare, stitcher, interval] in
            do {
                let source = try await prepare()
                guard let self, self.valid(current), !Task.isCancelled else { source.stop(); return }
                self.source = source; self.phase = .capturing
                while !Task.isCancelled, self.valid(current), self.phase == .capturing {
                    let image = try await source.next()
                    guard !Task.isCancelled, self.valid(current) else { return }
                    let update = try await stitcher.append(image)
                    guard !Task.isCancelled, self.valid(current) else { return }
                    self.receive(update)
                    if self.phase != .capturing { source.stop(); return }
                    try await Task.sleep(for: interval)
                }
            } catch is CancellationError { }
            catch {
                guard let self, self.generation == current, self.phase != .finishing, self.phase != .closed else { return }
                self.fail("长截图已停止：请检查来源窗口、选区大小、屏幕录制权限和安全输入状态。")
            }
        }
    }
    private func valid(_ token: Int) -> Bool { token == generation && phase != .closed && allowed() }
    private func receive(_ update: ScrollStitchUpdate) {
        thumbnail = update.thumbnail; height = update.height
        switch update.outcome {
        case .started, .added, .unchanged: message = "在原窗口缓慢向下滚动，完成后点击下方按钮。"
        case .ambiguous: message = "内容重复或固定区域变化，暂未追加。请小幅滚动或回到上一位置。"
        case .gap: message = "滚动过快或重叠不足，请向上回到已捕获内容附近。"
        case .reversed: message = "已回到前面的内容。继续向下滚动即可，重复内容不会追加。"
        case .limit: phase = .limited; message = height > 0 ? "已到高度、帧数或内存上限，可完成已有长截图。" : "选区过大，无法在内存预算内拼接。请取消并缩小选区。"
        }
    }
    func finish() {
        guard canFinish, allowed() else { return }
        phase = .finishing; message = "正在生成长截图…"
        sampling?.cancel(); source?.stop()
        let current = generation
        finishing = Task { [weak self, stitcher] in
            do {
                try Task.checkCancellation()
                let image = try await stitcher.finish()
                await stitcher.reset()
                guard let self, !Task.isCancelled, self.valid(current) else { return }
                self.thumbnail = nil; self.height = 0; self.phase = .closed
                self.protection?.cancel(); self.source = nil; self.sampling = nil
                self.onComplete(image)
            } catch {
                guard let self, self.generation == current, self.phase != .closed else { return }
                self.fail("无法生成长截图，已释放本次采集内容。")
            }
        }
    }
    func cancel() {
        guard phase != .closed else { return }
        clear(); onCancel()
    }
    private func fail(_ message: String) {
        guard phase != .closed else { return }
        clear(); onFailure(message)
    }
    private func clear() {
        generation += 1; phase = .closed
        sampling?.cancel(); sampling = nil; finishing?.cancel(); finishing = nil
        protection?.cancel(); protection = nil; source?.stop(); source = nil
        thumbnail = nil; height = 0
        Task { [stitcher] in await stitcher.reset() }
    }
}
