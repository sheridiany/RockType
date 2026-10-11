import AppKit
import XCTest
import RoarkTCore
@testable import RoarkTApp

@MainActor final class IconResourcesTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func run(_ arguments: [String], executable: URL = URL(fileURLWithPath: "/usr/bin/xcrun")) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
        return data
    }

    private func plist(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    }

    private func bitmap(_ size: NSSize, scale: Int, flipped: Bool = false, draw: () -> Void) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        // bitmap.size already sets the backing scale. Scaling again clips @2x.
        if flipped {
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: flipped)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func write(_ rep: NSBitmapImageRep, to url: URL) throws {
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    private func withAppearance(_ appearance: NSAppearance, draw: () throws -> Void) throws {
        var result: Result<Void, Error>!
        appearance.performAsCurrentDrawingAppearance { result = Result { try draw() } }
        try result.get()
    }

    private func render(_ image: NSImage, name: String, sizes: [Int], into output: URL) throws {
        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            try withAppearance(try XCTUnwrap(NSAppearance(named: appearance))) {
                for points in sizes {
                    for scale in [1, 2] {
                        let size = NSSize(width: points, height: points)
                        let rep = try bitmap(size, scale: scale) {
                            image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
                        }
                        XCTAssertEqual(rep.pixelsWide, points * scale)
                        XCTAssertGreaterThan(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)!.alphaComponent, 0.9)
                        for x in [0, rep.pixelsWide - 1] { for y in [0, rep.pixelsHigh - 1] {
                            XCTAssertLessThan(rep.colorAt(x: x, y: y)!.alphaComponent, 0.1,
                                              "rounded icon must not acquire solid or cropped corners")
                        } }
                        try write(rep, to: output.appendingPathComponent("\(name)-\(suffix)-\(points)@\(scale)x.png"))
                    }
                }
            }
        }
    }

    func testCompiledIconsAndTemplateAppearances() throws {
        let fm = FileManager.default
        let folder = ProcessInfo.processInfo.environment["ROARKT_ICON_RENDER_DIR"]
        let output = folder.map { URL(fileURLWithPath: $0) }
            ?? fm.temporaryDirectory.appendingPathComponent("RockType-icons-" + UUID().uuidString)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        defer { if folder == nil { try? fm.removeItem(at: output) } }
        for (name, icon, inputs, sourceInfo) in [
            ("App", "AppIcon", ["Assets/AppIcon.icon"], "App/Info.plist"),
            ("Input", "Rime", ["InputMethod/Assets.xcassets", "InputMethod/Rime.icon"], "InputMethod/resources/Info.plist")
        ] {
            let bundleURL = output.appendingPathComponent(name + ".bundle")
            let resources = bundleURL.appendingPathComponent("Contents/Resources")
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            let partial = output.appendingPathComponent(name + "-partial.plist")
            _ = try run(["actool"] + inputs.map { root.appendingPathComponent($0).path }
                + ["--compile", resources.path, "--app-icon", icon, "--platform", "macosx",
                   "--minimum-deployment-target", "14.0", "--output-partial-info-plist", partial.path])
            let emitted = try plist(partial), source = try plist(root.appendingPathComponent(sourceInfo))
            let file = try XCTUnwrap(source["CFBundleIconFile"] as? String)
            XCTAssertEqual(file.replacingOccurrences(of: ".icns", with: ""), emitted["CFBundleIconFile"] as? String)
            XCTAssertTrue(fm.fileExists(atPath: resources.appendingPathComponent(icon + ".icns").path))
            var info = emitted
            info["CFBundleIdentifier"] = name == "App" ? Identifiers.appBundleID : Identifiers.inputMethodBundleID
            info["CFBundlePackageType"] = "BNDL"
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
            let car = try run(["assetutil", "--info", resources.appendingPathComponent("Assets.car").path])
            try car.write(to: output.appendingPathComponent(name + "-assets.json"))
            let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: car) as? [[String: Any]])
            let appearances = Set(entries.filter { $0["AssetType"] as? String == "IconImageStack" }
                .compactMap { $0["Appearance"] as? String })
            XCTAssertTrue(appearances.contains("NSAppearanceNameAqua"))
            XCTAssertTrue(appearances.contains("NSAppearanceNameDarkAqua"))
            for points in [16, 32, 128, 256, 512] {
                XCTAssertTrue(entries.contains { ($0["Name"] as? String) == icon && ($0["Scale"] as? Int) == 2
                    && ($0["PixelWidth"] as? Int) == points * 2 }, "\(icon) missing \(points)pt @2x")
            }
            let bundle = try XCTUnwrap(Bundle(url: bundleURL))
            let image = try XCTUnwrap(bundle.image(forResource: NSImage.Name(icon)))
            XCTAssertFalse(image.isTemplate)
            XCTAssertGreaterThanOrEqual(image.representations.map(\.pixelsWide).max() ?? 0, 1024)
            try render(image, name: name, sizes: [16, 32, 64, 128, 256, 512], into: output)
        }
        let pdf = output.appendingPathComponent("roarktMenuTemplate.pdf")
        _ = try run(["swift", root.appendingPathComponent("scripts/generate-menu-icon.swift").path, pdf.path])
        let inputMenu = try XCTUnwrap(NSImage(contentsOf: pdf))
        inputMenu.isTemplate = true // the system recognizes the resource's Template suffix
        let appMenu = AppDelegate.statusImage()
        XCTAssertTrue(appMenu.isTemplate)
        XCTAssertEqual(appMenu.accessibilityDescription, "RockType")
        XCTAssertEqual(inputMenu.size, NSSize(width: 22, height: 16))
        XCTAssertEqual(appMenu.size, NSSize(width: 18, height: 18))
        for (name, image) in [("menu-app", appMenu), ("menu-input", inputMenu)] {
            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                let themed = try XCTUnwrap(NSAppearance(named: appearance))
                try withAppearance(themed) {
                    for scale in [1, 2] {
                        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 34, height: 24))
                        button.appearance = themed
                        button.isBordered = false
                        button.image = image
                        button.imagePosition = .imageOnly
                        button.imageScaling = .scaleNone
                        button.contentTintColor = suffix == "dark" ? .white : .black
                        let rep = try bitmap(button.frame.size, scale: scale, flipped: button.isFlipped) {
                            button.cell!.draw(withFrame: button.bounds, in: button)
                        }
                        var ink = 0
                        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                            if c.alphaComponent > 0.8 {
                                ink += 1
                                XCTAssertEqual(c.redComponent, suffix == "dark" ? 1 : 0, accuracy: 0.05)
                            }
                        } }
                        XCTAssertGreaterThan(ink, 15 * scale * scale, "template must be nonempty and visibly tinted")
                        for x in 0..<rep.pixelsWide {
                            XCTAssertLessThan(rep.colorAt(x: x, y: 0)!.alphaComponent, 0.1)
                            XCTAssertLessThan(rep.colorAt(x: x, y: rep.pixelsHigh - 1)!.alphaComponent, 0.1)
                        }
                        try write(rep, to: output.appendingPathComponent("\(name)-\(suffix)@\(scale)x.png"))
                    }
                }
            }
        }
        // Previous packaged artifacts use the identical renderer, never the desktop.
        if let baseline = ProcessInfo.processInfo.environment["ROARKT_ICON_BASELINE_DIR"] {
            let before = URL(fileURLWithPath: baseline)
            for (name, icon) in [("App", "AppIcon"), ("Input", "Rime")] {
                let bundle = try XCTUnwrap(Bundle(url: before.appendingPathComponent(name + ".bundle")))
                let image = try XCTUnwrap(bundle.image(forResource: NSImage.Name(icon)))
                try render(image, name: name, sizes: [16, 32, 64, 128, 256, 512], into: before)
            }
        }
    }

    func testModernDarkIconRetainsTheRCounter() throws {
        let found = try run(["--find", "actool"])
        let actool = URL(fileURLWithPath: String(decoding: found, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        let contents = actool.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // The Icon Composer exporter is distinct from the actool-compatible ictool
        // wrapper in Developer/usr/bin. Neither starts the GUI app.
        let exporter = contents.appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: exporter.path),
                          "Icon Composer exporter unavailable; modern appearance needs manual verification")
        let folder = ProcessInfo.processInfo.environment["ROARKT_ICON_RENDER_DIR"]
        let output = folder.map { URL(fileURLWithPath: $0).appendingPathComponent("modern") }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("RockType-modern-icons-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { if folder == nil { try? FileManager.default.removeItem(at: output) } }
        var phases: [(URL, URL, Bool)] = [(root, output, true)]
        if let baseline = ProcessInfo.processInfo.environment["ROARKT_ICON_BASELINE_DIR"] {
            let before = URL(fileURLWithPath: baseline)
            let images = before.appendingPathComponent("modern")
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            phases.append((before, images, false))
        }
        for (base, destination, current) in phases {
            for (name, relative, oldRelative) in [("App", "Assets/AppIcon.icon", "AppIcon.icon"),
                                                  ("Input", "InputMethod/Rime.icon", "Rime.icon")] {
                let document = base.appendingPathComponent(current ? relative : oldRelative)
                for rendition in ["Default", "Dark"] {
                    for size in (folder == nil ? [16, 128] : [16, 32, 64, 128, 256, 512]) {
                        for scale in [1, 2] {
                            let path = destination.appendingPathComponent("\(name)-\(rendition)-\(size)@\(scale)x.png")
                            _ = try run([document.path, "--export-image", "--output-file", path.path,
                                "--platform", "macOS", "--rendition", rendition,
                                "--width", String(size), "--height", String(size), "--scale", String(scale)], executable: exporter)
                            let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: path)))
                            XCTAssertEqual(rep.pixelsWide, size * scale)
                            XCTAssertEqual(rep.pixelsHigh, size * scale)
                            if current {
                                // The center of the R's bowl must show the blue background.
                                // A layer-wide solid fill used to close this counter in Dark.
                                let counter = try XCTUnwrap(rep.colorAt(x: Int(Double(rep.pixelsWide) * 0.53),
                                    y: Int(Double(rep.pixelsHigh) * 0.39))?.usingColorSpace(.deviceRGB))
                                XCTAssertGreaterThan(counter.blueComponent - counter.redComponent, 0.25,
                                    "\(name) \(rendition) \(size)@\(scale)x: R counter was filled")
                            }
                        }
                    }
                }
            }
        }
    }

    func testLegacyInputIconSlotsMatchTheirPixelSizes() throws {
        let folder = root.appendingPathComponent("InputMethod/Assets.xcassets/Rime.appiconset")
        let data = try Data(contentsOf: folder.appendingPathComponent("Contents.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(json["images"] as? [[String: String]])
        XCTAssertEqual(entries.count, 10)
        var slots = Set<String>()
        for entry in entries {
            let size = try XCTUnwrap(entry["size"]), scale = try XCTUnwrap(entry["scale"])
            let points = try XCTUnwrap(Int(size.components(separatedBy: "x")[0]))
            let factor = try XCTUnwrap(Int(scale.replacingOccurrences(of: "x", with: "")))
            let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: folder.appendingPathComponent(try XCTUnwrap(entry["filename"])))))
            XCTAssertEqual(image.pixelsWide, points * factor)
            XCTAssertEqual(image.pixelsHigh, points * factor)
            XCTAssertTrue(image.hasAlpha)
            slots.insert(size + "@" + scale)
        }
        for size in [16, 32, 128, 256, 512] { for scale in [1, 2] {
            XCTAssertTrue(slots.contains("\(size)x\(size)@\(scale)x"))
        } }
    }
}
