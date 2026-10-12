import AppKit
import RoarkTPlatform
import RoarkTCore
import SwiftUI
import QuartzCore
import os

/// Retain in AppDelegate, call start/stop, and bind HotkeyCenter.screenshotAction to capture().
@MainActor final class ScreenshotCoordinator {
    private var pendingTemplateID: String?
    private var running = false
    private let suppliedHistory: ScreenshotHistory?
    private(set) lazy var history = suppliedHistory ?? ScreenshotHistory(allowed: { [weak self] in self?.historyAllowed ?? false })
    private lazy var historyPanel = ScreenshotHistoryPanelController(history: history,
        allowed: { [weak self] in self?.historyAllowed ?? false },
        open: { [weak self] entry in self?.openHistory(entry) },
        action: { [weak self] entry, action in self?.historyAction(entry, action: action) },
        pinningAllowed: { [weak self] in self?.enabledFeatures.pinning ?? false })
    private var generation = 0
    private lazy var importer: ScreenshotImportController = {
        let importer = ScreenshotImportController(allowed: { [weak self] in self?.featureAllowed ?? false })
        importer.onImage = { [weak self] image, origin, recognize in
            guard let self, self.running, self.featureAllowed else { return }
            self.openImage(image, origin: origin)
            if recognize { self.session?.runOCR() }
        }
        importer.onBatch = { [weak self] images in self?.presentBatch(images) }
        importer.onNotice = { [weak self] in self?.onNotice($0) }
        return importer
    }()
    private let suppliedSaveAs: ScreenshotSaveAsController?
    private lazy var saveAs = suppliedSaveAs ?? ScreenshotSaveAsController(allowed: { [weak self] in self?.featureCaptureAllowed ?? false })
    private var saving = false
    private var scrollCapture: ScrollCaptureController?
    private let scrollHUD = ScrollCaptureHUD()
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
    var rememberImageConfirmation: (Bool) -> Void = { SettingsStore.shared.settings.screenshot.skipImageAIConfirmation = $0 }
    var performText: (OperationRequest) -> Void = { _ in }
    var imageCompleted: (OperationResult, OperationTemplate) -> Void = { _, _ in }
    private var previewPanel: NSPanel?
    private(set) var session: ScreenshotSession?
    private var batch: ScreenshotBatch?
    private var imageOpenPanel: NSOpenPanel?
    var onSelection: (CGImage) -> Void = { _ in }
    /// Numeric diagnostics only; also permits measuring the actual presentation boundary in tests.
    var onOverlayTiming: ((Double) -> Void)?
    private let captureFrames: () async throws -> [ScreenCapture.Frame]
    private let allowed: () -> Bool
    private let captureAllowed: () -> Bool
    private let elementQuery: CaptureElementQuery
    private var elementSnapshot: CaptureAccessibility.Snapshot?
    private var captureDesktopTop: CGFloat = 0
    private let readClipboard: () throws -> Data?
    private let presentPreview: (NSPanel) -> Void

    init(captureFrames: @escaping () async throws -> [ScreenCapture.Frame] = { try await ScreenCapture.capture() },
         allowed: (() -> Bool)? = nil,
         history: ScreenshotHistory? = nil,
         elementQuery: CaptureElementQuery = CaptureElementQuery(),
         saveAs: ScreenshotSaveAsController? = nil,
         readClipboard: @escaping () throws -> Data? = { try Clipboard.shared.readPNG() },
         presentPreview: @escaping (NSPanel) -> Void = { panel in panel.center(); panel.orderFrontRegardless() }) {
        self.suppliedHistory = history
        self.captureFrames = captureFrames
        self.allowed = allowed ?? { SecureInput.status() == .allowed }
        self.captureAllowed = allowed ?? { ScreenCapture.isReadable }
        self.elementQuery = elementQuery
        self.suppliedSaveAs = saveAs
        self.readClipboard = readClipboard; self.presentPreview = presentPreview
    }
    var enabledFeatures: FeatureSettings { readSettings().enabledFeatures }
    private var featureAllowed: Bool { enabledFeatures.screenshot && allowed() }
    private var featureCaptureAllowed: Bool { enabledFeatures.screenshot && captureAllowed() }
    private var historyAllowed: Bool { enabledFeatures.screenshot && enabledFeatures.screenshotHistory && allowed() }
    private var warming = false
    func settingsChanged() {
        guard running else { return }
        history.configure(readSettings().screenshot)
        history.setEnabled(enabledFeatures.screenshot && enabledFeatures.screenshotHistory)
        if !enabledFeatures.screenshotHistory { historyPanel.close() }
        if enabledFeatures.screenshot && !warming {
            warming = true; ScreenCapture.startWarming(); warmupTask = Task { await OCR.prewarm() }
        } else if !enabledFeatures.screenshot {
            warming = false; warmupTask?.cancel(); warmupTask = nil; ScreenCapture.stopWarming()
            cancel(); closePreview(); historyPanel.close()
        }
        for canvas in overlays.canvases.values { canvas.pinningEnabled = enabledFeatures.pinning }
    }
    private var warmupTask: Task<Void, Never>?
    private static let timing = Logger(subsystem: Identifiers.appBundleID, category: "ScreenshotTiming")
    func start() {
        guard !running else { return }
        running = true
        history.onNotice = { [weak self] in self?.onNotice($0) }
        history.setEnabled(enabledFeatures.screenshot && enabledFeatures.screenshotHistory)
        history.start(readSettings().screenshot)
        PinnedImageController.shared.onAction = { [weak self] image, action in
            guard let self, self.running, self.featureAllowed else { return }
            self.openImage(image, origin: action == .translate ? "贴图 · 核对文字后点击翻译" : "贴图")
            if action == .save { self.session?.save() }
            else if action == .translateImage { self.session?.translateImage() }
            else if action == .barcodes { self.session?.recognizeCodes() }
            else if action == .translate { self.session?.prepareImage(action: .translate) }
            else { self.session?.runOCR(copyAfter: action == .copyText) }
        }
        settingsChanged()
    }
    func stop() { running = false; warming = false; historyPanel.close(); history.stop(); warmupTask?.cancel(); warmupTask = nil; ScreenCapture.stopWarming(); cancel(); closePreview(); PinnedImageController.shared.closeAll() }
    func cancel() {
        pendingTemplateID = nil
        generation += 1
        let scroll = scrollCapture; scrollCapture = nil
        scroll?.onCancel = {}; scroll?.cancel(); scrollHUD.close()
        elementQuery.cancel(); elementSnapshot = nil
        saving = false; saveAs.cancel()
        imageOpenPanel?.cancel(nil); imageOpenPanel = nil
        importer.cancel()
        captureTask?.cancel(); captureTask = nil
        protectionTask?.cancel(); protectionTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor); self.globalKeyMonitor = nil }
        let overlayWasShown = overlays.close()
        hidden.forEach { $0.orderFrontRegardless() }; hidden.removeAll()
        // Nonactivating panels return borrowed key focus when closed. Restore the source only
        // if a subsequent native dialog actually activated us, never if the user switched apps.
        if overlayWasShown, NSApp.isActive, let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
    }
    func capture(templateID: String? = nil) {
        guard running, featureCaptureAllowed else { return }
        let started = CACurrentMediaTime()
        cancel(); pendingTemplateID = templateID
        let current = generation
        captureDesktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: captureDesktopTop - mouse.y)
        elementQuery.start(at: point) { [weak self] snapshot in
            guard let self, current == self.generation else { return }
            self.elementSnapshot = snapshot
            if let snapshot {
                for canvas in self.overlays.canvases.values {
                    guard let screen = canvas.window?.frame else { continue }
                    canvas.installElements(CaptureSmartSelection.local(snapshot, screen: screen, desktopTop: self.captureDesktopTop))
                }
            }
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
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
                if !self.featureCaptureAllowed { self.cancel(); return }
            }
        }
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let frames = try await self.captureFrames()
                guard !Task.isCancelled, current == self.generation, self.featureCaptureAllowed else { return }
                guard !frames.isEmpty else { throw ScreenCapture.Failure.unavailable }
                self.show(frames)
                CATransaction.flush()
                let elapsed = (CACurrentMediaTime() - started) * 1000
                Self.timing.info("overlay_ms \(elapsed, privacy: .public)")
                self.onOverlayTiming?(elapsed)
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
        if event.type == .rightMouseDown {
            // Only our active overlays own this gesture. Keep text/IME context menus intact,
            // including an edit on another display; do not commit it via the outside-click path.
            guard let canvas = event.window?.contentView as? CaptureCanvas,
                  overlays.canvases.values.contains(where: { $0 === canvas }) else { return event }
            if event.window?.firstResponder is CaptureTextView || overlays.canvases.values.contains(where: \.isEditingText) { return event }
            cancel(); return nil
        }
        if event.type == .leftMouseDown, event.window?.contentView is CaptureCanvas {
            for canvas in overlays.canvases.values { canvas.finishTextEditingIfOutside(event) }
        }
        return event
    }
    private func show(_ frames: [ScreenCapture.Frame]) {
        // SCK already excludes this process. Keep live windows intact until every overlay is ready.
        let floating = (NSApp?.windows ?? []).filter { $0.isVisible && $0.level != .normal }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for frame in frames {
            let panel = CapturePanel(captureRect: frame.rect)
            let view = CaptureCanvas(frame: CGRect(origin: .zero, size: frame.rect.size), image: frame.image, windows: frame.windows)
            let displayID = frame.displayID
            overlays.add(panel: panel, canvas: view, displayID: displayID)
            view.allowed = { [weak self] in self?.featureCaptureAllowed ?? false }
            view.pinningEnabled = enabledFeatures.pinning
            view.roundedCorners = readSettings().screenshot.roundedCorners ?? true
            view.toolStyles = readSettings().screenshot.annotationStyles ?? [:]
            if let elementSnapshot {
                view.installElements(CaptureSmartSelection.local(elementSnapshot, screen: frame.rect, desktopTop: captureDesktopTop))
            }
            view.onStyleChange = { [weak self] tool, style in
                guard let self else { return }
                self.writeAnnotationStyle(tool, style)
                for canvas in self.overlays.canvases.values { canvas.toolStyles[tool.rawValue] = style }
            }
            view.onCancel = { [weak self] in self?.cancel() }
            view.onScrollCapture = { [weak self, weak view] in
                guard let self, let view else { return }
                self.beginScrollCapture(view, frame: frame)
            }
            view.onComplete = { [weak self, weak view] image in
                guard let self, let view, self.featureCaptureAllowed else { return }
                if let id = self.pendingTemplateID {
                    self.lastSelection = (displayID, view.selection)
                    self.cancel(); self.openImage(image, origin: "截图", historyID: self.history.record(image))
                    self.session?.runTemplate(id)
                    return
                }
                do {
                    try ScreenshotOutput.shared.copyImage(image)
                    self.lastSelection = (displayID, view.selection)
                    self.history.record(image)
                    self.cancel(); self.onSelection(image)
                } catch { view.showNotice("无法复制图片，请重试。") }
            }
            view.onSave = { [weak self, weak view] image in
                guard let self, let view, self.featureCaptureAllowed else { return }
                let url: URL
                do { url = try ScreenshotOutput.shared.save(image) }
                catch { view.showNotice("保存失败，请检查截图保存目录及写入权限。") ; return }
                self.history.record(image)
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
                guard let self, let view, self.enabledFeatures.pinning, self.featureCaptureAllowed else { return }
                guard self.featureAllowed else { view.showNotice("贴图暂不可用，请检查辅助功能权限与安全输入状态。"); return }
                let selection = view.selection
                let rect = CaptureGeometry.globalScreenRect(selection, screen: screenRect)
                // Restore hidden windows before giving the new pin keyboard focus.
                self.cancel()
                if PinnedImageController.shared.pin(image, at: rect) {
                    self.history.record(image)
                    self.lastSelection = (displayID, selection)
                } else { self.onNotice("无法贴图，请检查安全输入状态和显示器。") }
            }
            view.onRestore = { [weak self, weak view] in
                guard let self, self.featureCaptureAllowed, let previous = self.lastSelection,
                      self.overlays.restore(displayID: previous.displayID, rect: previous.rect) else {
                    view?.showNotice("没有可恢复的选区，或原显示器已断开。")
                    return
                }
            }

            view.onOCRCopy = { [weak self, weak view] image in
                guard let self else { return }
                guard self.featureAllowed else { view?.showNotice("OCR 暂不可用，请检查辅助功能权限与安全输入状态。"); return }
                self.cancel(); self.openImage(image, origin: "截图", historyID: self.history.record(image))
                self.session?.runOCR(copyAfter: true)
            }
            view.onPreview = { [weak self, weak view] image in
                guard let self, let view, self.featureCaptureAllowed else { return }
                guard self.featureAllowed else { view.showNotice("预览暂不可用，请检查辅助功能权限与安全输入状态。"); return }
                self.lastSelection = (displayID, view.selection)
                self.cancel(); self.openImage(image, origin: "截图", historyID: self.history.record(image))
            }
            panel.acceptsMouseMovedEvents = true
            let mouse = NSEvent.mouseLocation
            view.updateHover(at: CGPoint(x: mouse.x - frame.rect.minX, y: frame.rect.maxY - mouse.y))
        }
        CATransaction.commit()
        overlays.present(at: NSEvent.mouseLocation) {
            self.hidden = floating
            floating.forEach { $0.orderOut(nil) }
            self.closePreview(); self.historyPanel.close()
            // Closed previews must not be restored by cancel().
            self.hidden.removeAll { $0.contentView == nil }
        }
    }
    private func beginScrollCapture(_ canvas: CaptureCanvas, frame: ScreenCapture.Frame) {
        guard featureAllowed, canvas.selection.width >= 32, canvas.selection.height >= 32 else {
            canvas.showNotice("请选取至少 32 × 32 点的区域，并确认辅助功能与安全输入状态。"); return
        }
        let selection = canvas.selection
        guard let window = frame.windows.first(where: { $0.contains(CGPoint(x: selection.midX, y: selection.midY)) }), window.contains(selection) else {
            canvas.showNotice("长截图的选区必须完整位于同一个窗口内。"); return
        }
        let region = CaptureGeometry.globalScreenRect(selection, screen: frame.rect)
        let expectedWindow = CaptureGeometry.globalScreenRect(window, screen: frame.rect)
        let pid = previousApp?.processIdentifier
        let rounded = readSettings().screenshot.roundedCorners ?? true
        lastSelection = (frame.displayID, selection)
        cancel() // Releases frozen full-screen images, restores the source app, and removes overlay monitors.
        let current = generation
        let controller = ScrollCaptureController(allowed: { [weak self] in self?.featureAllowed ?? false }, prepare: {
            try await ScrollRegionCapture.prepare(selection: region, expectedWindow: expectedWindow, expectedPID: pid)
        })
        scrollCapture = controller
        controller.onCancel = { [weak self] in
            guard let self, self.generation == current else { return }; self.cancel()
        }
        controller.onFailure = { [weak self] message in
            guard let self, self.generation == current else { return }; self.cancel(); self.onNotice(message)
        }
        controller.onComplete = { [weak self] image in
            guard let self, self.generation == current, self.featureAllowed else { return }
            self.completeScrollCapture(image, region: region, rounded: rounded)
        }
        scrollHUD.show(controller, near: region); controller.start()
    }
    /// One finalized scroll result shares the normal screenshot history and editable OCR cache.
    func completeScrollCapture(_ image: CGImage, region: CGRect, rounded: Bool) {
        guard running, featureAllowed, region.width > 0 else { return }
        let scale = CGFloat(image.width) / region.width
        guard let result = ScreenshotExport.render(image: image,
            pointSize: CGSize(width: region.width, height: CGFloat(image.height) / scale), roundedCorners: rounded) else {
            cancel(); onNotice("无法生成长截图，请缩小选区后重试。"); return
        }
        cancel(); openImage(result, origin: "滚动长截图", historyID: history.record(result))
    }
    func saveSelection(_ image: CGImage, canvas: CaptureCanvas, displayID: CGDirectDisplayID) {
        guard featureCaptureAllowed, !saving else { return }
        let current = generation
        saving = true
        overlays.suspend()
        saveAs.present(image: image, format: readSettings().screenshot.format) { [weak self, weak canvas] outcome in
            guard let self, current == self.generation, let canvas else { return }
            self.saving = false
            guard self.featureCaptureAllowed else { self.cancel(); return }
            if outcome == .saved {
                self.history.record(image)
                self.lastSelection = (displayID, canvas.selection); self.cancel(); return
            }
            self.overlays.resume(focusing: canvas)
            if outcome == .failed { canvas.showNotice("无法保存图片，请重试或选择其他位置。") }
        }
    }
    func openClipboardImage(recognize: Bool = false) {
        guard running, featureAllowed else { return }
        cancel(); closePreview()
        do {
            guard let data = try readClipboard() else { onNotice("剪贴板中没有图片。"); return }
            importer.load(data, origin: "剪贴板图片", recognize: recognize)
        } catch { onNotice("无法读取剪贴板图片，请重新复制后重试。") }
    }
    func openImageFiles() {
        guard running, featureAllowed, imageOpenPanel == nil else { return }
        let panel = NSOpenPanel(); imageOpenPanel = panel
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.prompt = "识别图片"; panel.message = "最多 10 张，解码后总计 128 MB；图片仅在本机识别。"
        panel.begin { [weak self] response in
            guard let self, self.imageOpenPanel === panel else { return }
            self.imageOpenPanel = nil
            guard response == .OK, self.running, self.featureAllowed else { return }
            self.openImageBatch(panel.urls)
        }
    }
    func openImageBatch(_ urls: [URL]) {
        guard running, featureAllowed else { return }
        cancel(); closePreview()
        importer.load(urls)
    }
    private func presentBatch(_ images: [CGImage]) {
        guard running, featureAllowed, !images.isEmpty else { return }
        let sessions = images.enumerated().map { index, image in
            let value = ScreenshotSession(image: image, origin: "批量图片 \(index + 1)", settings: self.readSettings,
                verified: self.imageCapabilityVerified, allowed: { [weak self] in self?.featureAllowed ?? false }, rememberImageConfirmation: self.rememberImageConfirmation)
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
    }
    @discardableResult func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard running, featureAllowed, let provider = providers.first(where: { ScreenshotImageImport.type(for: $0) != nil }),
              let type = ScreenshotImageImport.type(for: provider) else { return false }
        cancel(); closePreview()
        importer.load(provider, type: type)
        return true
    }
    func closePreview() {
        let oldBatch = batch; batch = nil; oldBatch?.close()
        let old = session; session = nil; old?.close()
        previewPanel?.orderOut(nil); previewPanel?.contentView = nil; previewPanel = nil
    }
    func openImage(_ image: CGImage, origin: String, complete: Bool = false, historyID: UUID? = nil, cachedText: String? = nil) {
        guard running, featureAllowed else { return }
        closePreview()
        let value = ScreenshotSession(image: image, origin: origin, settings: readSettings,
            verified: imageCapabilityVerified, allowed: { [weak self] in self?.featureAllowed ?? false }, rememberImageConfirmation: rememberImageConfirmation)
        session = value
        if let historyID {
            value.onTextChanged = { [weak self] text in self?.history.updateText(text, id: historyID) }
        }
        if let cachedText { value.text = cachedText }
        value.onClose = { [weak self] in self?.closePreview() }
        value.configureVision = configureVision
        value.performText = performText
        value.imageCompleted = imageCompleted
        value.start()
        if complete { value.copyImage(closeAfter: true); return }
        let panel = CapturePanel(contentRect: CGRect(x: 0, y: 0, width: ScreenshotPreviewContent.width, height: ScreenshotPreviewContent.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ScreenshotPreviewContent(session: value))
        previewPanel = panel; presentPreview(panel)
    }

    func showHistory() {
        guard running, enabledFeatures.screenshot, enabledFeatures.screenshotHistory else { return }
        guard featureAllowed else { onNotice("截图历史暂不可用，请检查辅助功能权限与安全输入状态。"); return }
        cancel(); history.configure(readSettings().screenshot); historyPanel.show()
    }
    func clearTransientHistory() { historyPanel.close(); if !history.onDisk { history.clear() } }
    func openHistory(_ entry: ScreenshotHistoryEntry) {
        guard enabledFeatures.screenshotHistory, running, featureAllowed else { return }
        openImage(entry.image, origin: "截图历史", historyID: entry.id, cachedText: entry.text)
    }
    func historyAction(_ entry: ScreenshotHistoryEntry, action: ScreenshotHistoryView.Action) {
        guard enabledFeatures.screenshotHistory, running, featureAllowed else { return }
        switch action {
        case .copy:
            do { try ScreenshotOutput.shared.copyImage(entry.image); onNotice("图片已复制") }
            catch { onNotice("无法复制图片，请重试。") }
        case .save:
            saveAs.present(image: entry.image, format: readSettings().screenshot.format) { [weak self] outcome in
                if outcome == .failed { self?.onNotice("无法保存图片，请重试或选择其他位置。") }
            }
        case .pin:
            guard enabledFeatures.pinning, let screen = NSScreen.main else { return }
            let width = min(480, CGFloat(entry.image.width))
            let size = CGSize(width: width, height: width * CGFloat(entry.image.height) / CGFloat(entry.image.width))
            let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
            if !PinnedImageController.shared.pin(entry.image, at: frame) { onNotice("无法贴图，请检查安全输入状态。") }
        }
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
        animationBehavior = .none
        isOpaque = true
        backgroundColor = .black
        alphaValue = 1
        hasShadow = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
