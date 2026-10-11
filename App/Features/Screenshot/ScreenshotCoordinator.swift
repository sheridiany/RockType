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
    private var canvases: [CGDirectDisplayID: CaptureCanvas] = [:]
    private var lastSelection: (displayID: CGDirectDisplayID, rect: CGRect)?
    private var hidden: [NSWindow] = []
    /// The app the user was in; it gets focus back when the overlay closes.
    private var previousApp: NSRunningApplication?
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
    private(set) var session: ScreenshotSession?
    private var batch: ScreenshotBatch?
    private var imageOpenPanel: NSOpenPanel?
    var onSelection: (CGImage) -> Void = { _ in }
    private let captureFrames: () async throws -> [ScreenCapture.Frame]
    private let allowed: () -> Bool
    private let readClipboard: () throws -> Data?
    private let presentPreview: (NSPanel) -> Void

    init(captureFrames: @escaping () async throws -> [ScreenCapture.Frame] = { try await ScreenCapture.capture() },
         allowed: @escaping () -> Bool = { SecureInput.status() == .allowed },
         readClipboard: @escaping () throws -> Data? = { try Clipboard.shared.readPNG() },
         presentPreview: @escaping (NSPanel) -> Void = { panel in panel.center(); panel.orderFrontRegardless() }) {
        self.captureFrames = captureFrames; self.allowed = allowed
        self.readClipboard = readClipboard; self.presentPreview = presentPreview
    }
    private var warmupTask: Task<Void, Never>?
    private static let timing = Logger(subsystem: Identifiers.appBundleID, category: "ScreenshotTiming")
    func start() {
        guard !running else { return }
        running = true
        PinnedImageController.shared.onAction = { [weak self] image, action in
            guard let self, self.running, self.allowed() else { return }
            self.openImage(image, origin: action == .translate ? "贴图 · 核对文字后点击翻译" : "贴图")
            if action == .save { self.session?.save() }
            else { self.session?.runOCR(copyAfter: action == .copyText) }
        }
        ScreenCapture.startWarming()
        warmupTask = Task { await OCR.prewarm() }
    }
    func stop() { running = false; warmupTask?.cancel(); warmupTask = nil; ScreenCapture.stopWarming(); cancel(); closePreview(); PinnedImageController.shared.closeAll() }
    func cancel() {
        generation += 1
        imageOpenPanel?.cancel(nil); imageOpenPanel = nil
        importTask?.cancel(); importTask = nil; importProgress?.cancel(); importProgress = nil
        captureTask?.cancel(); captureTask = nil
        protectionTask?.cancel(); protectionTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor); self.globalKeyMonitor = nil }
        let overlayWasShown = !panels.isEmpty
        panels.forEach { $0.orderOut(nil); $0.contentView = nil }; panels.removeAll(); canvases.removeAll()
        hidden.forEach { $0.orderFrontRegardless() }; hidden.removeAll()
        // Without this the overlay's focus stays on RockType, which has no text input, and the
        // menu bar input source icon goes blank until the user clicks another app.
        if overlayWasShown, let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
    }
    func capture() {
        guard running, allowed() else { return }
        let started = CACurrentMediaTime()
        cancel(); closePreview()
        let current = generation
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        hidden = (NSApp?.windows ?? []).filter { $0.isVisible && $0.level != .normal }
        hidden.forEach { $0.orderOut(nil) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.routeCanvasEvent(event)
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self else { return }
            // IME candidate windows can belong to another process. Never close an active text edit here.
            if !self.canvases.values.contains(where: \.isEditingText) { self.cancel() }
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
    /// Keep native NSTextView/IME key handling ahead of the screenshot's Escape shortcut.
    func routeCanvasEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 {
            if event.window?.firstResponder is CaptureTextView || canvases.values.contains(where: \.isEditingText) { return event }
            cancel(); return nil
        }
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           event.window?.contentView is CaptureCanvas {
            for canvas in canvases.values { canvas.finishTextEditingIfOutside(event) }
        }
        return event
    }
    private func show(_ frames: [ScreenCapture.Frame]) {
        for frame in frames {
            let panel = CapturePanel(captureRect: frame.rect)
            let view = CaptureCanvas(frame: CGRect(origin: .zero, size: frame.rect.size), image: frame.image, windows: frame.windows)
            let displayID = frame.displayID
            canvases[displayID] = view
            view.allowed = allowed
            view.onCancel = { [weak self] in self?.cancel() }
            view.onComplete = { [weak self, weak view] image in
                guard let self, let view, self.allowed() else { return }
                do {
                    try ScreenshotOutput.shared.copyImage(image)
                    self.lastSelection = (displayID, view.selection)
                    self.cancel(); self.onSelection(image)
                } catch { view.showNotice("无法复制图片，请重试。") }
            }
            view.onSave = { [weak self, weak view] image in
                guard let self, let view, self.allowed() else { return }
                let url: URL
                do { url = try ScreenshotOutput.shared.save(image) }
                catch { view.showNotice("保存失败，请检查截图保存目录及写入权限。") ; return }
                self.lastSelection = (displayID, view.selection)
                do { try ScreenshotOutput.shared.copyPath(url); self.cancel() }
                catch { view.showNotice("PNG 已保存，但路径复制失败。") }
            }
            let screenRect = frame.rect
            view.onPin = { [weak self, weak view] image in
                guard let self, let view, self.allowed() else { return }
                let selection = view.selection
                let rect = CaptureGeometry.globalScreenRect(selection, screen: screenRect)
                // Restore hidden windows before giving the new pin keyboard focus.
                self.cancel()
                if PinnedImageController.shared.pin(image, at: rect) {
                    self.lastSelection = (displayID, selection)
                } else { self.onNotice("无法贴图，请检查安全输入状态和显示器。") }
            }
            view.onRestore = { [weak self, weak view] in
                guard let self, self.allowed(), let previous = self.lastSelection,
                      let target = self.canvases[previous.displayID],
                      !CaptureGeometry.restored(previous.rect, bounds: target.bounds).isEmpty else {
                    view?.showNotice("没有可恢复的选区，或原显示器已断开。")
                    return
                }
                for canvas in self.canvases.values { canvas.restore(.zero) }
                target.restore(previous.rect)
                target.window?.makeKey(); target.window?.makeFirstResponder(target)
            }
            view.onOCRCopy = { [weak self] image in
                guard let self, self.allowed() else { return }
                self.cancel(); self.openImage(image, origin: "截图")
                self.session?.runOCR(copyAfter: true)
            }
            view.onPreview = { [weak self, weak view] image in
                guard let self, let view, self.allowed() else { return }
                self.lastSelection = (displayID, view.selection)
                self.cancel(); self.openImage(image, origin: "截图")
            }
            panel.contentView = view; panels.append(panel)
            panel.acceptsMouseMovedEvents = true
            let mouse = NSEvent.mouseLocation
            view.updateHover(at: CGPoint(x: mouse.x - frame.rect.minX, y: frame.rect.maxY - mouse.y))
            panel.orderFrontRegardless()
            if frame.rect.contains(NSEvent.mouseLocation) {
                // Keys (Esc, ↩, R, P) only reach the overlay while RockType is active.
                NSApp.activate()
                panel.makeKey(); panel.makeFirstResponder(view)
            }
        }
    }
    func openClipboardImage(recognize: Bool = false) {
        guard running, allowed() else { return }
        cancel(); closePreview()
        do {
            guard let data = try readClipboard() else { onNotice("剪贴板中没有图片。"); return }
            decodeImport(data, origin: "剪贴板图片", current: generation, recognize: recognize)
        } catch { onNotice("无法读取剪贴板图片，请重新复制后重试。") }
    }
    func openImageFiles() {
        guard running, allowed(), imageOpenPanel == nil else { return }
        let panel = NSOpenPanel(); imageOpenPanel = panel
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.prompt = "识别图片"; panel.message = "最多 10 张，解码后总计 128 MB；图片仅在本机识别。"
        panel.begin { [weak self] response in
            guard let self, self.imageOpenPanel === panel else { return }
            self.imageOpenPanel = nil
            guard response == .OK, self.running, self.allowed() else { return }
            self.openImageBatch(panel.urls)
        }
    }
    func openImageBatch(_ urls: [URL]) {
        guard running, allowed() else { return }
        cancel(); closePreview(); let current = generation
        importTask = Task { [weak self] in
            do {
                let worker = Task.detached { try ScreenshotBatch.load(urls) }
                let images = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, !Task.isCancelled, self.running, self.allowed(), self.generation == current else { return }
                let sessions = images.enumerated().map { index, image in
                    let value = ScreenshotSession(image: image, origin: "批量图片 \(index + 1)", settings: self.readSettings,
                        verified: self.imageCapabilityVerified, allowed: self.allowed)
                    value.performText = self.performText; value.configureVision = self.configureVision
                    value.imageCompleted = self.imageCompleted
                    value.onClose = { [weak self] in self?.closePreview() }
                    value.start(); return value
                }
                let batch = ScreenshotBatch(sessions: sessions); self.batch = batch
                let panel = CapturePanel(contentRect: CGRect(x: 0, y: 0, width: ScreenshotPreviewContent.width,
                    height: ScreenshotPreviewContent.height + 48), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = .floating; panel.isReleasedWhenClosed = false
                panel.contentView = NSHostingView(rootView: ScreenshotBatchPreview(batch: batch))
                self.previewPanel = panel; self.presentPreview(panel)
                batch.current.runOCR()
            } catch {
                guard let self, !Task.isCancelled, self.generation == current else { return }
                self.onNotice("无法打开这批图片。请选择最多 10 张 PNG、JPEG 或 TIFF，总像素内存不超过 128 MB。")
            }
        }
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
    private func decodeImport(_ data: Data, origin: String, current: Int, recognize: Bool = false) {
        importTask = Task { [weak self] in
            do {
                let worker = Task.detached { try ScreenshotImageImport.decode(data) }
                let image = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, !Task.isCancelled, self.generation == current, self.allowed() else { return }
                self.openImage(image, origin: origin)
                if recognize { self.session?.runOCR() }
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
        let oldBatch = batch; batch = nil; oldBatch?.close()
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
        let panel = CapturePanel(contentRect: CGRect(x: 0, y: 0, width: ScreenshotPreviewContent.width, height: ScreenshotPreviewContent.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ImagePreviewView(session: value))
        previewPanel = panel; presentPreview(panel)
    }

}
final class CapturePanel: NSPanel {
    /// A screenshot is shown from a background menu-bar app; it must not disappear on deactivation.
    convenience init(captureRect: CGRect) {
        self.init(contentRect: captureRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = true
        backgroundColor = .black
        alphaValue = 1
        hasShadow = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
