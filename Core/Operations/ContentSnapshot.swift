import Foundation
import CoreGraphics

/// Runtime-only immutable content. Never persist or log this value.
public struct ContentSnapshot: Equatable, Sendable, Identifiable {
    public struct Source: Equatable, Sendable {
        public let pid: Int32
        public let bundleID: String?
        public let applicationName: String
        public let windowIdentifier: String?
        public init(pid: Int32, bundleID: String? = nil, applicationName: String,
                    windowIdentifier: String? = nil) {
            self.pid = pid; self.bundleID = bundleID; self.applicationName = applicationName
            self.windowIdentifier = windowIdentifier
        }
    }
    public enum CaptureMethod: String, Sendable { case accessibility, copyFallback, paste }
    public let id: UUID
    public let text: String
    public let source: Source
    public let method: CaptureMethod
    /// AppKit screen coordinates, in points.
    public let selectionRect: CGRect?
    public let capturedAt: Date
    public init(id: UUID = UUID(), text: String, source: Source, method: CaptureMethod,
                selectionRect: CGRect? = nil, capturedAt: Date = Date()) {
        self.id = id; self.text = text; self.source = source; self.method = method
        self.selectionRect = selectionRect; self.capturedAt = capturedAt
    }
}
