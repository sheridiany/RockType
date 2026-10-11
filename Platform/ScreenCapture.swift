import AppKit
import ScreenCaptureKit

/// Metadata is warmed in advance; pixels are captured only on explicit action.
@MainActor public enum ScreenCapture {
    public struct Frame: Sendable {
        public let displayID: CGDirectDisplayID
        public let rect: CGRect
        public let image: CGImage
        /// Front-to-back window rectangles in this display's top-left canvas coordinates.
        public let windows: [CGRect]
        public init(displayID: CGDirectDisplayID, rect: CGRect, image: CGImage, windows: [CGRect] = []) {
            self.displayID = displayID; self.rect = rect; self.image = image; self.windows = windows
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
    /// Explicit screen capture needs screen-recording permission, not AX permission.
    /// Keep fail-closed password/unavailable handling when AX inspection is available.
    public static var isReadable: Bool { permitsCapture(SecureInput.status()) }
    public static func permitsCapture(_ status: SecureInput.Status) -> Bool {
        switch status { case .allowed, .noPermission: true; case .secureInput, .unavailable: false }
    }
    private static func requireReadable() throws {
        let status = SecureInput.status()
        guard permitsCapture(status) else {
            throw status == .unavailable ? PlatformReadError.unavailable : PlatformReadError.secureInput
        }
    }
    public enum Failure: Error { case permission, unavailable }
    public static func capture() async throws -> [Frame] {
        try requireReadable()
        guard Permissions.status(for: .screenRecording) == .granted else { throw Failure.permission }
        let content: SCShareableContent
        if let cached = self.content { content = cached }
        else { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true); self.content = content }
        try Task.checkCancellation()
        try requireReadable()
        // Snapshot at capture time, not the older warmed SCShareableContent window list.
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var captures: [Task<Frame, Error>] = []
        defer { captures.forEach { $0.cancel() } }
        for screen in NSScreen.screens {
            try Task.checkCancellation()
            try requireReadable()
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
            let windows = CaptureWindowGeometry.rectangles(windowInfo, display: rect, desktopTop: desktopTop,
                ownPID: ProcessInfo.processInfo.processIdentifier)
            captures.append(Task { @MainActor in
                try Task.checkCancellation()
                try requireReadable()
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                try Task.checkCancellation()
                try requireReadable()
                return Frame(displayID: display.displayID, rect: rect, image: image, windows: windows)
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

/// Window-server coordinates are top-left based; AppKit screen frames are bottom-left based.
public enum CaptureWindowGeometry {
    public static func rectangles(_ windows: [[String: Any]], display: CGRect, desktopTop: CGFloat,
                                  ownPID: Int32) -> [CGRect] {
        let displayTop = CGRect(x: display.minX, y: desktopTop - display.maxY,
                                width: display.width, height: display.height)
        return windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber, pid.int32Value != ownPID,
                  let level = window[kCGWindowLayer as String] as? NSNumber, level.intValue == 0,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0.01,
                  let values = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: values as CFDictionary),
                  rect.width >= 40, rect.height >= 40,
                  window[kCGWindowOwnerName as String] as? String != "Dock" else { return nil }
            let clipped = rect.intersection(displayTop)
            guard !clipped.isNull, !clipped.isEmpty else { return nil }
            return clipped.offsetBy(dx: -displayTop.minX, dy: -displayTop.minY)
        }
    }
}
