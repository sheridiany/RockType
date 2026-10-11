import AppKit
import SwiftUI
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor @Test func selectionToolbarRendersThemesAndStaysNonactivating() throws {
    _ = NSApplication.shared
    // Set this only when exporting review evidence; normal test runs leave no artifacts.
    let output = ProcessInfo.processInfo.environment["ROARKT_SELECTION_RENDER_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }
    if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
    var settings = AppSettings()
    for crowded in [false, true] {
        if crowded {
            for index in 0..<12 {
                let id = "custom-\(index)"
                settings.templates.append(.init(id: id, name: "自定义操作 \(index)", icon: "text.bubble", prompt: ""))
                settings.selection.toolbarActions.append(id)
            }
        }
        for dark in [false, true] {
            let view = LiveSelectionToolbar(actions: SelectionToolbarAction.configured(in: settings),
                maximumWidth: Tokens.Size.resultWidth, perform: { _ in }, renderingSnapshot: true)
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(image.width <= Int(Tokens.Size.resultWidth * 2))
            #expect(image.height > 0)
            if let output {
                let bitmap = NSBitmapImageRep(cgImage: image)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: output.appendingPathComponent("toolbar-\(crowded ? "crowded" : "normal")-\(dark ? "dark" : "light").png"))
            }
        }
    }
    let window = SelectionToolbarWindow()
    defer { window.hide() }
    let snapshot = ContentSnapshot(text: "Synthetic selection", source: .init(pid: 42, applicationName: "Test"), method: .accessibility)
    window.show(snapshot: snapshot, settings: AppSettings(), perform: { _ in })
    let panel = try #require(NSApp.windows.first(where: { window.contains($0) }))
    #expect(!panel.canBecomeKey && !panel.canBecomeMain)
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.frame.width <= Tokens.Size.resultWidth)
    window.hide()
    #expect(!window.isVisible)
}
