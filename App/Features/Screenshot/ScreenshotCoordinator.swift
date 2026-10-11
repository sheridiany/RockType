import AppKit
import RoarkTPlatform
import RoarkTCore
import SwiftUI
import UniformTypeIdentifiers
import QuartzCore
import os

/// Retain in AppDelegate, call start/stop, and bind HotkeyCenter.screenshotAction to capture().
@MainActor final class ScreenshotCoordinator {
    private var running = false
    private var generation = 0
    private var importTask: Task<Void, Never>?
    private var importProgress: Progress?
    private var captureTask: Task<Void, Never>?
    private var protectionTask: Task<Void, Never>?
    private var panels: [NSPanel] = []
    private var hidden: [NSWindow] = []
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    var onNotice: (String) -> Void = { _ in }
    var onPermissionRequired: () -> Void = { Permissions.openSettings(for: .screenRecording) }
    var readSettings: () -> AppSettings = { .defaults }
    /// Must validate the exact current connection/model against the settings connection-test result.
    var imageCapabilityVerified: (AIConnectionSettings, String) -> Bool = { _, _ in false }
    var configureVision: () -> Void = {}
    var performText: (OperationRequest) -> Void = { _ in }
    var imageCompleted: (OperationResult, OperationTemplate) -> Void = { _, _ in }
    private var previewPanel: NSPanel?
    private var session: ScreenshotSession?
    var onSelection: (CGImage) -> Void = { _ in }
    private let captureFrames: () async throws -> [ScreenCapture.Frame]
    private let allowed: () -> Bool

    init(captureFrames: @escaping () async throws -> [ScreenCapture.Frame] = { try await ScreenCapture.capture() },
         allowed: @escaping () -> Bool = { SecureInput.status() == .allowed }) {
        self.captureFrames = captureFrames; self.allowed = allowed
    }
    private var warmupTask: Task<Void, Never>?
    private static let timing = Logger(subsystem: Identifiers.appBundleID, category: "ScreenshotTiming")
    func start() {
        guard !running else { return }
        running = true
        ScreenCapture.startWarming()
        warmupTask = Task { await OCR.prewarm() }
    }
    func stop() { running = false; warmupTask?.cancel(); warmupTask = nil; ScreenCapture.stopWarming(); cancel(); closePreview() }
    func cancel() {
        generation += 1
        importTask?.cancel(); importTask = nil; importProgress?.cancel(); importProgress = nil
        captureTask?.cancel(); captureTask = nil
        protectionTask?.cancel(); protectionTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor); self.globalKeyMonitor = nil }
        panels.forEach { $0.orderOut(nil); $0.contentView = nil }; panels.removeAll()
        hidden.forEach { $0.orderFrontRegardless() }; hidden.removeAll()
    }
    func capture() {
        guard running, allowed() else { return }
        let started = CACurrentMediaTime()
        cancel(); closePreview()
        let current = generation
        hidden = (NSApp?.windows ?? []).filter { $0.isVisible && $0.level != .normal }
        hidden.forEach { $0.orderOut(nil) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel(); return nil }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel() }
        }
        protectionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self else { return }
                if !self.allowed() { self.cancel(); return }
            }
        }
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let frames = try await self.captureFrames()
                guard !Task.isCancelled, current == self.generation, self.allowed() else { return }
                self.show(frames)
                CATransaction.flush()
                Self.timing.info("overlay_ms \((CACurrentMediaTime() - started) * 1000, privacy: .public)")
            } catch {
                guard current == self.generation else { return }
                self.cancel()
                if error as? ScreenCapture.Failure == .permission { self.onPermissionRequired() }
                else if !(error is CancellationError) { self.onNotice("无法截取屏幕，请检查屏幕录制权限后重试。") }
            }
        }
    }
    private func show(_ frames: [ScreenCapture.Frame]) {
        for frame in frames {
            let panel = CapturePanel(contentRect: frame.rect, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            let view = CaptureCanvas(frame: CGRect(origin: .zero, size: frame.rect.size), image: frame.image, windows: frame.windows)
            view.onCancel = { [weak self] in self?.cancel() }
            view.onComplete = { [weak self] image in
                guard let self, self.allowed() else { return }
                self.cancel(); self.onSelection(image)
                self.openImage(image, origin: "截图", complete: true)
            }
            view.onPreview = { [weak self] image in
                guard let self, self.allowed() else { return }
                self.cancel(); self.openImage(image, origin: "截图")
            }
            panel.contentView = view; panels.append(panel)
            panel.acceptsMouseMovedEvents = true
            let mouse = NSEvent.mouseLocation
            view.updateHover(at: CGPoint(x: mouse.x - frame.rect.minX, y: frame.rect.maxY - mouse.y))
            panel.orderFrontRegardless()
            if frame.rect.contains(NSEvent.mouseLocation) { panel.makeKey(); panel.makeFirstResponder(view) }
        }
    }
    func openClipboardImage() {
        guard running, allowed() else { return }
        cancel(); closePreview()
        do {
            guard let data = try Clipboard.shared.readPNG() else { onNotice("剪贴板中没有图片。"); return }
            decodeImport(data, origin: "剪贴板图片", current: generation)
        } catch { onNotice("无法读取剪贴板图片，请重新复制后重试。") }
    }
    @discardableResult func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard running, allowed(), let provider = providers.first(where: { ScreenshotImageImport.type(for: $0) != nil }),
              let type = ScreenshotImageImport.type(for: provider) else { return false }
        cancel(); closePreview(); let current = generation
        importProgress = provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.allowed(), self.generation == current else { return }
                guard let data else { self.onNotice("无法读取拖入的图片。"); return }
                if type == UTType.fileURL.identifier {
                    guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                        self.onNotice("请拖入本机图片文件。"); return
                    }
                    self.importTask = Task { [weak self] in
                        do {
                            let worker = Task.detached { try ScreenshotImageImport.decode(ScreenshotImageImport.read(url)) }
                            let image = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                            guard let self, !Task.isCancelled, self.generation == current, self.allowed() else { return }
                            self.openImage(image, origin: "拖入图片")
                        } catch {
                            guard let self, !Task.isCancelled, self.generation == current else { return }
                            self.importFailure(error)
                        }
                    }
                } else { self.decodeImport(data, origin: "拖入图片", current: current) }
            }
        }
        return true
    }
    private func decodeImport(_ data: Data, origin: String, current: Int) {
        importTask = Task { [weak self] in
            do {
                let worker = Task.detached { try ScreenshotImageImport.decode(data) }
                let image = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, !Task.isCancelled, self.generation == current, self.allowed() else { return }
                self.openImage(image, origin: origin)
            } catch {
                guard let self, !Task.isCancelled, self.generation == current else { return }
                self.importFailure(error)
            }
        }
    }
    private func importFailure(_ error: Error) {
        onNotice(error as? ScreenshotImageImport.Failure == .tooLarge
            ? "图片过大：支持最大 40 MB、6400 万像素，请缩小后重试。" : "图片无法打开，请使用 PNG、JPEG 或 TIFF 图片。")
    }
    func closePreview() {
        let old = session; session = nil; old?.close()
        previewPanel?.orderOut(nil); previewPanel?.contentView = nil; previewPanel = nil
    }
    func openImage(_ image: CGImage, origin: String, complete: Bool = false) {
        guard running, allowed() else { return }
        closePreview()
        let value = ScreenshotSession(image: image, origin: origin, settings: readSettings,
            verified: imageCapabilityVerified, allowed: allowed)
        session = value
        value.onClose = { [weak self] in self?.closePreview() }
        value.configureVision = configureVision
        value.performText = performText
        value.imageCompleted = imageCompleted
        value.start()
        if complete { value.copyImage(closeAfter: true); return }
        let panel = CapturePanel(contentRect: CGRect(x: 0, y: 0, width: Tokens.Size.resultMaxHeight, height: ScreenshotPreviewContent.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ImagePreviewView(session: value))
        panel.center(); previewPanel = panel; panel.orderFrontRegardless()
    }

}
private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
