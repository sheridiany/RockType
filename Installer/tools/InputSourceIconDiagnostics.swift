// MIT. Read-only diagnostics: never registers, selects, enables or restarts anything.
import AppKit
import Carbon

@MainActor
enum InputSourceIconDiagnostics {
    static let modeIDs = [Identifiers.pinyinInputSourceID, Identifiers.flypyInputSourceID]
    static let iconKeys = ["tsInputModeMenuIconFileKey", "tsInputModeAlternateMenuIconFileKey", "tsInputModePaletteIconFileKey"]

    static func image(at url: URL) -> [String: Any] {
        var report: [String: Any] = ["url": url.absoluteURL.absoluteString, "readable": false, "nonempty": false]
        guard url.isFileURL, let image = NSImage(contentsOf: url),
              image.size.width > 0, image.size.height > 0,
              image.size.width <= 256, image.size.height <= 256,
              let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              bitmap.pixelsWide <= 1024, bitmap.pixelsHigh <= 1024 else { return report }
        var ink = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { ink += 1 }
        }
        report["readable"] = true
        report["nonempty"] = ink > 0
        report["sizePoints"] = [image.size.width, image.size.height]
        report["visiblePixels"] = ink
        return report
    }

    static func bundle(at url: URL) throws -> (report: [String: Any], valid: Bool) {
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == Identifiers.inputMethodBundleID,
              let component = info["ComponentInputModeDict"] as? [String: Any],
              let modes = component["tsInputModeListKey"] as? [String: [String: Any]] else {
            return (["error": "Unexpected input method manifest"], false)
        }
        let resources = url.appendingPathComponent("Contents/Resources").resolvingSymlinksInPath()
        var valid = true
        var reports: [[String: Any]] = []
        for id in modeIDs {
            let mode = modes[id] ?? [:]
            var icons: [String: Any] = [:]
            for key in iconKeys {
                guard let name = mode[key] as? String, !name.isEmpty else {
                    icons[key] = ["error": "Missing resource declaration"]
                    valid = false
                    continue
                }
                let iconURL = resources.appendingPathComponent(name).resolvingSymlinksInPath().standardizedFileURL
                guard iconURL.path.hasPrefix(resources.path + "/") else {
                    icons[key] = ["error": "Resource escapes bundle"]
                    valid = false
                    continue
                }
                let icon = image(at: iconURL)
                icons[key] = icon
                valid = valid && icon["nonempty"] as? Bool == true
            }
            reports.append(["id": id, "hasIconLabels": mode["TISIconLabels"] != nil, "icons": icons])
        }
        return (["bundle": url.path, "modes": reports], valid)
    }

    static func property(_ source: TISInputSource, _ key: CFString) -> Any? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
    }

    static func preferenceEvidence(domain: String, key: String) -> InputSourcePreferenceEvidence {
        InputSourcePreferenceEvidence(preference: CFPreferencesCopyValue(
            key as CFString, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
    }

    static func enablement() -> InputSourceEnablementState {
        let filter = [kTISPropertyBundleID as String: Identifiers.inputMethodBundleID] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
        var registered = Set<String>(), enabled = Set<String>(), selectable = Set<String>()
        for source in sources {
            guard let id = property(source, kTISPropertyInputSourceID) as? String,
                  InputSourceEnablement.registeredIDs.contains(id) else { continue }
            registered.insert(id)
            if property(source, kTISPropertyInputSourceIsEnabled) as? Bool == true { enabled.insert(id) }
            if property(source, kTISPropertyInputSourceIsSelectCapable) as? Bool == true { selectable.insert(id) }
        }
        return InputSourceEnablementState(registered: registered, enabled: enabled, selectable: selectable)
    }

    static func json<T: Encodable>(_ value: T) -> Any {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) ?? [:]
    }

    static func live() -> (report: [String: Any], valid: Bool) {
        let filter = [kTISPropertyBundleID as String: Identifiers.inputMethodBundleID] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
        var found = Set<String>()
        var valid = true
        let reports: [[String: Any]] = sources.compactMap { source in
            guard let id = property(source, kTISPropertyInputSourceID) as? String,
                  modeIDs.contains(id) else { return nil }
            found.insert(id)
            var report: [String: Any] = ["id": id,
                "enabled": property(source, kTISPropertyInputSourceIsEnabled) as? Bool ?? false,
                "selected": property(source, kTISPropertyInputSourceIsSelected) as? Bool ?? false,
                "selectable": property(source, kTISPropertyInputSourceIsSelectCapable) as? Bool ?? false,
                // IconRef is opaque, not a CF object. Absence is normal for PDF-backed modes.
                "hasIconRef": TISGetInputSourceProperty(source, kTISPropertyIconRef) != nil]
            if let url = property(source, kTISPropertyIconImageURL) as? URL {
                let icon = image(at: url)
                report["image"] = icon
                valid = valid && icon["nonempty"] as? Bool == true
            } else {
                report["image"] = ["error": "No image URL; IconRef rendering has not been verified"]
                valid = false
            }
            return report
        }
        let urls = LSCopyApplicationURLsForBundleIdentifier(Identifiers.inputMethodBundleID as CFString, nil)?
            .takeRetainedValue() as? [URL] ?? []
        return (["modes": reports, "missingModes": modeIDs.filter { !found.contains($0) },
                 "launchServicesURLs": urls.map(\.path), "menuAgent": menuAgent(),
                 "enablement": json(enablement()),
                 "preferenceEvidence": [
                    "authoritativeForVerification": false,
                    "com.apple.HIToolbox/AppleEnabledInputSources": json(preferenceEvidence(domain: "com.apple.HIToolbox", key: "AppleEnabledInputSources")),
                    "com.apple.inputsources/AppleEnabledThirdPartyInputSources": json(preferenceEvidence(domain: "com.apple.inputsources", key: "AppleEnabledThirdPartyInputSources"))
                 ]], valid && found.count == modeIDs.count)
    }

    static func menuAgent() -> [String: Any] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.apple.TextInputMenuAgent" }
        let trusted = AXIsProcessTrusted() // No permission prompt or mutation.
        var report: [String: Any] = ["runningCount": apps.count, "accessibilityAvailable": trusted]
        guard trusted else { return report }
        report["instances"] = apps.map { app -> [String: Any] in
            var menu: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                                      kAXExtrasMenuBarAttribute as CFString, &menu)
            var item: [String: Any] = ["pid": app.processIdentifier, "menuStatus": status.rawValue]
            guard status == .success, let menu, CFGetTypeID(menu) == AXUIElementGetTypeID() else { return item }
            var children: CFTypeRef?
            let childStatus = AXUIElementCopyAttributeValue(menu as! AXUIElement, kAXChildrenAttribute as CFString, &children)
            item["childrenStatus"] = childStatus.rawValue
            item["items"] = (children as? [AXUIElement] ?? []).map { child -> [String: Any] in
                var result: [String: Any] = [:]
                for (name, key, type) in [("position", kAXPositionAttribute, AXValueType.cgPoint),
                                          ("size", kAXSizeAttribute, AXValueType.cgSize)] {
                    var value: CFTypeRef?
                    let status = AXUIElementCopyAttributeValue(child, key as CFString, &value)
                    result[name + "Status"] = status.rawValue
                    guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { continue }
                    let ax = value as! AXValue
                    if type == .cgPoint {
                        var point = CGPoint.zero
                        if AXValueGetValue(ax, type, &point) { result[name] = [point.x, point.y] }
                    } else {
                        var size = CGSize.zero
                        if AXValueGetValue(ax, type, &size) { result[name] = [size.width, size.height] }
                    }
                }
                return result
            }
            return item
        }
        return report
    }

    static func run(bundleURL: URL?) -> Int32 {
        do {
            let (details, valid) = try bundleURL.map { try bundle(at: $0) } ?? live()
            var report = details
            report["resourceCheckPassed"] = valid
            report["scope"] = "Read-only resource/AX metadata; a passing result does not prove the menu icon is visible. No screenshots or field content collected."
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            FileHandle.standardOutput.write(data + Data("\n".utf8))
            return valid ? 0 : 1
        } catch {
            FileHandle.standardError.write(Data("Input-source icon diagnostic could not read the bundle manifest.\n".utf8))
            return 1
        }
    }
}
