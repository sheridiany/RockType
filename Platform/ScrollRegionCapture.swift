import AppKit
import ScreenCaptureKit

/// Explicit, short-lived sampling of one selected region of one external window.
/// A display filter INCLUDING only that window excludes our HUD and unrelated occluding windows.
@MainActor public final class ScrollRegionCapture {
    public enum Failure: Error { case permission, sourceChanged, invalidRegion, tooLarge, stopped }
    public struct Identity: Sendable, Equatable {
        public let windowID: CGWindowID
        public let pid: Int32
        public let bounds: CGRect // Quartz desktop logical coordinates
        public init(windowID: CGWindowID, pid: Int32, bounds: CGRect) { self.windowID = windowID; self.pid = pid; self.bounds = bounds }
    }
    private static let background = CGColor(gray: 1, alpha: 1)
    private var filter: SCContentFilter?
    private let configuration: SCStreamConfiguration
    private let identity: Identity
    private let screenFrames: [CGRect]
    private let screenScales: [CGFloat]
    private var stopped = false
    private init(filter: SCContentFilter, configuration: SCStreamConfiguration, identity: Identity) {
        self.filter = filter; self.configuration = configuration; self.identity = identity
        screenFrames = NSScreen.screens.map(\.frame); screenScales = NSScreen.screens.map(\.backingScaleFactor)
    }
    public static func target(in windows: [[String: Any]], selection: CGRect, ownPID: Int32) -> Identity? {
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber, pid.int32Value != ownPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0.01,
                  let values = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: values as CFDictionary), rect.contains(CGPoint(x: selection.midX, y: selection.midY)) else { continue }
            // Do not fall through an overlapping foreground window to a larger window behind it.
            guard rect.contains(selection), let id = window[kCGWindowNumber as String] as? NSNumber else { return nil }
            return .init(windowID: id.uint32Value, pid: pid.int32Value, bounds: rect)
        }
        return nil
    }
    /// AppKit global selection -> display-local, top-left logical crop. Pixel scale is applied only to output dimensions.
    public static func sourceRect(selection: CGRect, display: CGRect) -> CGRect {
        CGRect(x: selection.minX - display.minX, y: display.maxY - selection.maxY, width: selection.width, height: selection.height)
    }
    public static func prepare(selection: CGRect, expectedWindow: CGRect, expectedPID: Int32?) async throws -> ScrollRegionCapture {
        guard ScreenCapture.isReadable, Permissions.status(for: .screenRecording) == .granted else { throw Failure.permission }
        guard selection.width >= 32, selection.height >= 32,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(selection) }),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { throw Failure.invalidRegion }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        func quartz(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height) }
        let region = quartz(selection), displayRect = quartz(screen.frame)
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let identity = target(in: info, selection: region, ownPID: ProcessInfo.processInfo.processIdentifier),
              expectedPID == nil || identity.pid == expectedPID,
              identity.bounds.intersection(displayRect) == quartz(expectedWindow) else { throw Failure.sourceChanged }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == displayID.uint32Value }),
              let window = content.windows.first(where: { $0.windowID == identity.windowID && $0.owningApplication?.processID == identity.pid }) else { throw Failure.sourceChanged }
        let filter = SCContentFilter(display: display, including: [window])
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect(selection: selection, display: screen.frame)
        config.width = Int((region.width * scale).rounded()); config.height = Int((region.height * scale).rounded())
        guard config.width > 0, config.height > 0, config.width <= 16_384, config.height <= 8_192,
              config.width * config.height * 4 <= 40 * 1024 * 1024 else { throw Failure.tooLarge }
        config.showsCursor = false; config.backgroundColor = background
        let result = ScrollRegionCapture(filter: filter, configuration: config, identity: identity)
        try result.validate()
        return result
    }
    private func validate() throws {
        guard !stopped else { throw Failure.stopped }
        guard ScreenCapture.isReadable, Permissions.status(for: .screenRecording) == .granted else { throw Failure.permission }
        guard NSScreen.screens.map(\.frame) == screenFrames, NSScreen.screens.map(\.backingScaleFactor) == screenScales else { throw Failure.sourceChanged }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard front == identity.pid else { throw Failure.sourceChanged }
        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, identity.windowID) as? [[String: Any]] ?? []
        guard let window = info.first, (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
              (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == identity.pid,
              let values = window[kCGWindowBounds as String] as? [String: Any],
              CGRect(dictionaryRepresentation: values as CFDictionary) == identity.bounds else { throw Failure.sourceChanged }
    }
    public func next() async throws -> CGImage {
        try Task.checkCancellation(); try validate()
        guard let filter else { throw Failure.stopped }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation(); try validate()
        guard image.width == configuration.width, image.height == configuration.height else { throw Failure.sourceChanged }
        return image
    }
    public func stop() { stopped = true; filter = nil }
}
