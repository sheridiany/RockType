import AppKit
import RoarkTCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let gallery = GalleryWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "RoarkT"
        let menu = NSMenu()
        #if DEBUG
        let galleryItem = menu.addItem(withTitle: "设计面板…", action: #selector(showGallery), keyEquivalent: "")
        galleryItem.target = self
        menu.addItem(.separator())
        #endif
        menu.addItem(withTitle: "退出 RoarkT", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        if CommandLine.arguments.contains("--gallery") { gallery.show() }
    }

    @objc private func showGallery() { gallery.show() }
}
