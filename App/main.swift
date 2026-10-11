import AppKit

let app = NSApplication.shared
let arguments = Array(CommandLine.arguments.dropFirst())

// Render before creating a status item/window or entering the application event loop.
// An explicit NSApplication is sufficient; no screen capture or privacy permissions.
if arguments.contains("--render-gallery") {
    guard arguments.count == 2, arguments[0] == "--render-gallery", !arguments[1].isEmpty else {
        FileHandle.standardError.write(Data("用法：RoarkTApp --render-gallery <目录>\n".utf8))
        exit(EXIT_FAILURE)
    }
    app.setActivationPolicy(.prohibited)
    do {
        let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let count = try GalleryRenderer.render(to: directory)
        print("Gallery：已渲染 \(count) 张 PNG → \(directory.path)")
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("Gallery 渲染失败：\(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
