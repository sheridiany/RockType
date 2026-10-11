import AppKit
import RoarkTPlatform

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
    var onSelection: (CGImage) -> Void = { _ in }
    private let captureFrames: () async throws -> [ScreenCapture.Frame]
    private let allowed: () -> Bool

    init(captureFrames: @escaping () async throws -> [ScreenCapture.Frame] = { try await ScreenCapture.capture() },
         allowed: @escaping () -> Bool = { SecureInput.status() == .allowed }) {
        self.captureFrames = captureFrames; self.allowed = allowed
    }
    func start() { running = true }
    func stop() { running = false; cancel() }
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
        cancel()
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
            }
            panel.contentView = view; panels.append(panel)
            panel.orderFrontRegardless()
            if frame.rect.contains(NSEvent.mouseLocation) { panel.makeKey(); panel.makeFirstResponder(view) }
        }
    }
}
private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
