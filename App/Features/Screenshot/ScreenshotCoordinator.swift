import AppKit
import RoarkTPlatform
import RoarkTCore
import SwiftUI
import QuartzCore
import os

/// Retain in AppDelegate, call start/stop, and bind HotkeyCenter.screenshotAction to capture().
@MainActor final class ScreenshotCoordinator {
    private var running = false
    private var generation = 0
    private lazy var importer: ScreenshotImportController = {
        let importer = ScreenshotImportController(allowed: allowed)
        importer.onImage = { [weak self] image, origin in self?.openImage(image, origin: origin) }
        importer.onNotice = { [weak self] in self?.onNotice($0) }
        return importer
    }()
    private let saveAs: ScreenshotSaveAsController
    private var saving = false
    private var captureTask: Task<Void, Never>?
    private var protectionTask: Task<Void, Never>?
    private let overlays = CaptureOverlayGroup()
    private var lastSelection: (displayID: CGDirectDisplayID, rect: CGRect)?
    private var hidden: [NSWindow] = []
    /// The app the user was in; it gets focus back when the overlay closes.
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    var onNotice: (String) -> Void = { _ in }
    var onPermissionRequired: () -> Void = { Permissions.openSettings(for: .screenRecording) }
    var readSettings: () -> AppSettings = { .defaults }
    var writeAnnotationStyle: (ScreenshotTool, ScreenshotAnnotationStyle) -> Void = { tool, style in
        var styles = SettingsStore.shared.settings.screenshot.annotationStyles ?? [:]
        styles[tool.rawValue] = style
        SettingsStore.shared.settings.screenshot.annotationStyles = styles
    }
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
         allowed: @escaping () -> Bool = { SecureInput.status() == .allowed },
         saveAs: ScreenshotSaveAsController? = nil) {
        self.captureFrames = captureFrames; self.allowed = allowed
        self.saveAs = saveAs ?? ScreenshotSaveAsController(allowed: allowed)
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
        saving = false; saveAs.cancel()
        importer.cancel()
        captureTask?.cancel(); captureTask = nil
        protectionTask?.cancel(); protectionTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor); self.globalKeyMonitor = nil }
        let overlayWasShown = overlays.close()
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
            if !self.saving, !self.overlays.canvases.values.contains(where: \.isEditingText) { self.cancel() }
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
        if saving { return event } // NSSavePanel owns Escape and text input while overlays are hidden.
        if event.type == .keyDown, event.keyCode == 53 {
            if event.window?.firstResponder is CaptureTextView || overlays.canvases.values.contains(where: \.isEditingText) { return event }
            cancel(); return nil
        }
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           event.window?.contentView is CaptureCanvas {
            for canvas in overlays.canvases.values { canvas.finishTextEditingIfOutside(event) }
        }
        return event
    }
    private func show(_ frames: [ScreenCapture.Frame]) {
        for frame in frames {
            let panel = CapturePanel(captureRect: frame.rect)
            let view = CaptureCanvas(frame: CGRect(origin: .zero, size: frame.rect.size), image: frame.image, windows: frame.windows)
            let displayID = frame.displayID
            overlays.add(panel: panel, canvas: view, displayID: displayID)
            view.allowed = allowed
            view.roundedCorners = readSettings().screenshot.roundedCorners ?? true
            view.toolStyles = readSettings().screenshot.annotationStyles ?? [:]
            view.onStyleChange = { [weak self] tool, style in
                guard let self else { return }
                self.writeAnnotationStyle(tool, style)
                for canvas in self.overlays.canvases.values { canvas.toolStyles[tool.rawValue] = style }
            }
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
            view.onSaveAs = { [weak self, weak view] image in
                guard let self, let view else { return }
                self.saveSelection(image, canvas: view, displayID: displayID)
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
                      self.overlays.restore(displayID: previous.displayID, rect: previous.rect) else {
                    view?.showNotice("没有可恢复的选区，或原显示器已断开。")
                    return
                }
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
    func saveSelection(_ image: CGImage, canvas: CaptureCanvas, displayID: CGDirectDisplayID) {
        guard allowed(), !saving else { return }
        let current = generation
        saving = true
        overlays.suspend()
        saveAs.present(image: image, format: readSettings().screenshot.format) { [weak self, weak canvas] outcome in
            guard let self, current == self.generation, let canvas else { return }
            self.saving = false
            guard self.allowed() else { self.cancel(); return }
            if outcome == .saved {
                self.lastSelection = (displayID, canvas.selection); self.cancel(); return
            }
            self.overlays.resume(focusing: canvas)
            if outcome == .failed { canvas.showNotice("无法保存图片，请重试或选择其他位置。") }
        }
    }
    func openClipboardImage() {
        guard running, allowed() else { return }
        cancel(); closePreview()
        do {
            guard let data = try Clipboard.shared.readPNG() else { onNotice("剪贴板中没有图片。"); return }
            importer.load(data, origin: "剪贴板图片")
        } catch { onNotice("无法读取剪贴板图片，请重新复制后重试。") }
    }
    @discardableResult func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard running, allowed(), let provider = providers.first(where: { ScreenshotImageImport.type(for: $0) != nil }),
              let type = ScreenshotImageImport.type(for: provider) else { return false }
        cancel(); closePreview()
        importer.load(provider, type: type)
        return true
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
