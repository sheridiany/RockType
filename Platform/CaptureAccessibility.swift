import Foundation
import CoreGraphics
import Carbon
@preconcurrency import ApplicationServices

/// Capture-time geometry only. Never reads AXValue (text), title, description, selection or URL.
public enum CaptureAccessibility {
    public struct Snapshot: Sendable {
        /// Quartz/AX desktop coordinates: top-left origin, logical points.
        public let window: CGRect
        public let rectangles: [CGRect]
        public init(window: CGRect, rectangles: [CGRect]) { self.window = window; self.rectangles = rectangles }
    }
    public struct Target: Equatable, Sendable {
        public let pid: Int32
        public let window: CGRect
    }
    public static func target(at point: CGPoint, windows: [[String: Any]], ownPID: Int32) -> Target? {
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber, pid.int32Value != ownPID,
                  let layer = window[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0.01,
                  window[kCGWindowOwnerName as String] as? String != "Dock",
                  let values = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: values as CFDictionary), rect.contains(point) else { continue }
            return Target(pid: pid.int32Value, window: rect)
        }
        return nil
    }
    /// Call on a worker queue. Every AX message has its own timeout, within a total 100 ms budget.
    public static func snapshot(at point: CGPoint) -> Snapshot? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.100
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let target = target(at: point, windows: windows, ownPID: ProcessInfo.processInfo.processIdentifier) else { return nil }
        var protected = false
        func ready(_ element: AXUIElement) -> Bool {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0, !protected, !IsSecureEventInputEnabled(), AXIsProcessTrusted() else { return false }
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, pid == target.pid else { return false }
            return AXUIElementSetMessagingTimeout(element, Float(min(0.020, remaining))) == .success
        }
        func attribute(_ name: CFString, _ element: AXUIElement) -> CFTypeRef? {
            guard ready(element) else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
            return value
        }
        func rectangle(_ element: AXUIElement) -> CGRect? {
            guard ready(element) else { return nil }
            let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute] as CFArray
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
                  let values = values as? [Any], values.count == 4, values[0] is String else { return nil }
            if values[0] as? String == kAXSecureTextFieldSubrole || values[1] as? String == kAXSecureTextFieldSubrole {
                protected = true; return nil
            }
            guard CFGetTypeID(values[2] as CFTypeRef) == AXValueGetTypeID(), CFGetTypeID(values[3] as CFTypeRef) == AXValueGetTypeID() else { return nil }
            let position = values[2] as! AXValue, size = values[3] as! AXValue
            guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
            var p = CGPoint.zero, s = CGSize.zero
            guard AXValueGetValue(position, .cgPoint, &p), AXValueGetValue(size, .cgSize, &s),
                  p.x.isFinite, p.y.isFinite, s.width.isFinite, s.height.isFinite, s.width > 0, s.height > 0 else { return nil }
            let rect = CGRect(origin: p, size: s).intersection(target.window)
            return rect.isEmpty || rect.isNull ? nil : rect
        }
        let application = AXUIElementCreateApplication(target.pid)
        guard ready(application) else { return nil }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        var rectangles: [CGRect] = [], ancestors: [AXUIElement] = []
        var current: AXUIElement? = hit
        while let element = current, ancestors.count < 12, !protected {
            if ancestors.contains(where: { CFEqual($0, element) }) { break }
            ancestors.append(element)
            if let rect = rectangle(element), !rectangles.contains(rect) { rectangles.append(rect) }
            guard let parent = attribute(kAXParentAttribute as CFString, element), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = (parent as! AXUIElement)
        }
        // A bounded local neighbourhood improves hover selection without traversing an application's full tree.
        for parent in ancestors.prefix(4) where !protected && rectangles.count < 64 {
            guard ready(parent) else { break }
            var children: CFArray?
            guard AXUIElementCopyAttributeValues(parent, kAXChildrenAttribute as CFString, 0, 16, &children) == .success,
                  let children = children as? [AXUIElement] else { continue }
            for child in children where !protected && rectangles.count < 64 {
                if let rect = rectangle(child), !rectangles.contains(rect) { rectangles.append(rect) }
            }
        }
        guard !protected, !IsSecureEventInputEnabled(), AXIsProcessTrusted(), !rectangles.isEmpty else { return nil }
        return Snapshot(window: target.window, rectangles: rectangles)
    }
}
