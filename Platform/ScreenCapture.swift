import AppKit
import ScreenCaptureKit

/// Metadata is warmed in advance; pixels are captured only on explicit action.
@MainActor public enum ScreenCapture {
    public struct Frame: Sendable {
        public let displayID: CGDirectDisplayID
        public let rect: CGRect
        public let image: CGImage
        public init(displayID: CGDirectDisplayID, rect: CGRect, image: CGImage) {
            self.displayID = displayID; self.rect = rect; self.image = image
        }
    }
    private static var content: SCShareableContent?
    private static var refreshTask: Task<Void, Never>?
    private static var refreshGeneration = 0

    public static func startWarming() {
        guard refreshTask == nil else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask = Task {
            var previous: [NSDictionary] = []
            var previousScreens: [CGRect] = []
            while !Task.isCancelled {
                if SecureInput.status() == .allowed,
                   Permissions.status(for: .screenRecording) == .granted {
                    // Window-server metadata only, never pixels or titles retained in logs.
                    let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [NSDictionary] ?? []).map {
                        NSDictionary(dictionary: ["id": $0[kCGWindowNumber] ?? 0, "bounds": $0[kCGWindowBounds] ?? [:]])
                    }
                    let screens = NSScreen.screens.map(\.frame)
                    if content == nil || windows != previous || screens != previousScreens {
                        if let fresh = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                           !Task.isCancelled, generation == refreshGeneration {
                            content = fresh; previous = windows; previousScreens = screens
                        }
                    }
                } else { content = nil; previous = [] }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    public static func stopWarming() {
        refreshGeneration += 1
        refreshTask?.cancel(); refreshTask = nil; content = nil
    }
    public enum Failure: Error { case permission, unavailable }
    public static func capture() async throws -> [Frame] {
        try SecureInput.requireReadable()
        guard Permissions.status(for: .screenRecording) == .granted else { throw Failure.permission }
        let content: SCShareableContent
        if let cached = self.content { content = cached }
        else { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true); self.content = content }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var captures: [Task<Frame, Error>] = []
        defer { captures.forEach { $0.cancel() } }
        for screen in NSScreen.screens {
            try Task.checkCancellation()
            try SecureInput.requireReadable()
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
                throw Failure.unavailable
            }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            config.showsCursor = false
            let rect = screen.frame
            captures.append(Task { @MainActor in
                try Task.checkCancellation()
                try SecureInput.requireReadable()
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                try Task.checkCancellation()
                try SecureInput.requireReadable()
                return Frame(displayID: display.displayID, rect: rect, image: image)
            })
        }
        var frames: [Frame] = []
        for capture in captures {
            let frame = try await capture.value
            try Task.checkCancellation()
            frames.append(frame)
        }
        guard !frames.isEmpty else { throw Failure.unavailable }
        return frames
    }
}
