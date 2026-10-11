import AppKit
import ScreenCaptureKit

/// One-shot, memory-only capture. Call only in response to the screenshot action.
@MainActor public enum ScreenCapture {
    public struct Frame {
        public let displayID: CGDirectDisplayID
        public let rect: CGRect
        public let image: CGImage
        public init(displayID: CGDirectDisplayID, rect: CGRect, image: CGImage) {
            self.displayID = displayID; self.rect = rect; self.image = image
        }
    }
    public enum Failure: Error { case permission, unavailable }
    public static func capture() async throws -> [Frame] {
        try SecureInput.requireReadable()
        guard Permissions.status(for: .screenRecording) == .granted else { throw Failure.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var frames: [Frame] = []
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
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try Task.checkCancellation()
            try SecureInput.requireReadable()
            frames.append(Frame(displayID: display.displayID, rect: screen.frame, image: image))
        }
        guard !frames.isEmpty else { throw Failure.unavailable }
        return frames
    }
}
