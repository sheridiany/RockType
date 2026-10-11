import AppKit
import RoarkTPlatform
import RoarkTCore
import SwiftUI

/// Retain in AppDelegate, call start/stop, and bind HotkeyCenter.screenshotAction to capture().
@MainActor final class ScreenshotCoordinator {
    private var running = false
    private var generation = 0
    private var captureTask: Task<Void, Never>?
    private var protectionTask: Task<Void, Never>?
    private var panels: [NSPanel] = []
    private var hidden: [NSWindow] = []
    private var keyMonitor: Any?
    var onNotice: (String) -> Void = { _ in }
    var onPermissionRequired: () -> Void = { Permissions.openSettings(for: .screenRecording) }
    var readSettings: () -> AppSettings = { .defaults }
    /// Must validate the exact current connection/model against the settings connection-test result.
    var imageCapabilityVerified: (AIConnectionSettings, String) -> Bool = { _, _ in false }
    var configureVision: () -> Void = {}
    private let operations = OperationsEnvironment()
    private var previewPanel: NSPanel?
    private var resultPanel: NSPanel?
    private var session: ScreenshotSession?
    var onSelection: (CGImage) -> Void = { _ in }
    private let captureFrames: () async throws -> [ScreenCapture.Frame]
    private let allowed: () -> Bool

    init(captureFrames: @escaping () async throws -> [ScreenCapture.Frame] = { try await ScreenCapture.capture() },
         allowed: @escaping () -> Bool = { SecureInput.status() == .allowed }) {
        self.captureFrames = captureFrames; self.allowed = allowed
    }
    func start() { running = true; operations.start() }
    func stop() { running = false; cancel(); closePreview(); operations.stop() }
    func cancel() {
        generation += 1
        captureTask?.cancel(); captureTask = nil
        protectionTask?.cancel(); protectionTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        panels.forEach { $0.orderOut(nil); $0.contentView = nil }; panels.removeAll()
        hidden.forEach { $0.orderFrontRegardless() }; hidden.removeAll()
    }
    func capture() {
        guard running, allowed() else { return }
        cancel(); closePreview()
        let current = generation
        hidden = (NSApp?.windows ?? []).filter { $0.isVisible && $0.level != .normal }
        hidden.forEach { $0.orderOut(nil) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel(); return nil }
            return event
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
            let view = CaptureCanvas(frame: CGRect(origin: .zero, size: frame.rect.size), image: frame.image)
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
            panel.orderFrontRegardless()
            if frame.rect.contains(NSEvent.mouseLocation) { panel.makeKey(); panel.makeFirstResponder(view) }
        }
    }
    func closePreview() {
        let old = session; session = nil; old?.close()
        previewPanel?.orderOut(nil); previewPanel?.contentView = nil; previewPanel = nil
        resultPanel?.orderOut(nil); resultPanel?.contentView = nil; resultPanel = nil
    }
    func openImage(_ image: CGImage, origin: String, complete: Bool = false) {
        guard running, allowed() else { return }
        closePreview()
        let value = ScreenshotSession(image: image, origin: origin, settings: readSettings,
            verified: imageCapabilityVerified, runner: operations.makeRunner(connectionID: readSettings().ai.id), allowed: allowed)
        session = value
        value.onClose = { [weak self] in self?.closePreview() }
        value.configureVision = configureVision
        value.onResult = { [weak self] in self?.showResult() }
        value.start()
        if complete { value.copyImage(closeAfter: true); return }
        let panel = CapturePanel(contentRect: CGRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ImagePreviewView(session: value))
        panel.center(); previewPanel = panel; panel.orderFrontRegardless()
    }
    private func showResult() {
        guard let session else { return }
        resultPanel?.orderOut(nil)
        let panel = CapturePanel(contentRect: CGRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ScreenshotResultContent(session: session, close: { [weak self] in
            self?.session?.cancel(); self?.resultPanel?.orderOut(nil)
            self?.resultPanel?.contentView = nil; self?.resultPanel = nil
        }))
        panel.center(); resultPanel = panel; panel.orderFrontRegardless()
    }

}
private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
