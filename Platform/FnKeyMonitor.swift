import AppKit

/// A short tap is ignored. A chord cancels and cannot restart until Fn has been released.
public struct FnGesture: Sendable {
    public enum Action: Equatable, Sendable { case none, press, release, cancel }
    public private(set) var pending = false
    public private(set) var held = false
    private var previousFn = false
    public init() {}

    public mutating func flags(fn: Bool, keyCode: Int, otherModifiers: Bool, allowed: Bool) -> Action {
        let changed = previousFn != fn
        previousFn = fn
        if !allowed { return cancel() }
        if !fn {
            pending = false
            if held { held = false; return .release }
            return .none
        }
        if otherModifiers { return cancel() }
        if changed, keyCode == 63 || keyCode == 0 { pending = true }
        return .none
    }
    public mutating func holdElapsed() -> Action {
        guard pending else { return .none }
        pending = false; held = true
        return .press
    }
    public mutating func cancel() -> Action {
        pending = false
        let wasHeld = held
        held = false
        return wasHeld ? .cancel : .none
    }
    public mutating func reset() { self = FnGesture() }
}

/// Observes rather than consumes events. The system Fn action may need disabling in Keyboard settings.
@MainActor public final class FnKeyMonitor {
    public enum Event: Sendable { case press, release, cancel }
    public enum Failure: Error { case noPermission, unavailable }
    public var onEvent: (@MainActor (Event) -> Void)?
    public let minimumHold: Duration
    private var gesture = FnGesture()
    private var holdTask: Task<Void, Never>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    public init(minimumHold: Duration = .milliseconds(180)) { self.minimumHold = minimumHold }

    public func start() throws {
        stop()
        guard Accessibility.isTrusted() else { throw Failure.noPermission }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        guard globalMonitor != nil, localMonitor != nil else { stop(); throw Failure.unavailable }
        resignObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let resignObserver { NSWorkspace.shared.notificationCenter.removeObserver(resignObserver) }
        globalMonitor = nil; localMonitor = nil; resignObserver = nil
        cancel()
        gesture.reset()
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged else { cancel(); return }
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let action = gesture.flags(fn: event.modifierFlags.contains(.function), keyCode: Int(event.keyCode),
                                   otherModifiers: !modifiers.isEmpty, allowed: !SecureInput.isSecureInputActive())
        emit(action)
        if !gesture.pending { holdTask?.cancel(); holdTask = nil }
        if gesture.pending, holdTask == nil {
            holdTask = Task { @MainActor [weak self, minimumHold] in
                do { try await Task.sleep(for: minimumHold) } catch { return }
                guard let self else { return }
                self.holdTask = nil
                guard SecureInput.status() == .allowed else { self.cancel(); return }
                self.emit(self.gesture.holdElapsed())
            }
        }
    }
    private func cancel() {
        holdTask?.cancel(); holdTask = nil
        emit(gesture.cancel())
    }
    private func emit(_ action: FnGesture.Action) {
        switch action {
        case .none: break
        case .press: onEvent?(.press)
        case .release: onEvent?(SecureInput.status() == .allowed ? .release : .cancel)
        case .cancel: onEvent?(.cancel)
        }
    }

    isolated deinit {
        holdTask?.cancel()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let resignObserver { NSWorkspace.shared.notificationCenter.removeObserver(resignObserver) }
    }
}
