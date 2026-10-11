import AppKit
import SwiftUI

@MainActor
enum GalleryRenderer {
    enum RenderError: LocalizedError {
        case invalidCatalog
        case noImage(String)
        var errorDescription: String? {
            switch self {
            case .invalidCatalog: "Gallery 注册表为空、标识重复或包含非法文件名。"
            case .noImage(let name): "无法渲染 Gallery 图片：\(name)"
            }
        }
    }

    static func render(to directory: URL) throws -> Int {
        let entries = GalleryCatalog.entries
        let valid = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !entries.isEmpty, Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ entry in
                  [entry.surface, entry.state].allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(valid.contains) }
              }) else { throw RenderError.invalidCatalog }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var count = 0
        for entry in entries {
            for theme in GalleryTheme.allCases {
                let name = "\(entry.id)-\(theme.rawValue).png"
                let preview = GalleryPreview(entry: entry, theme: theme, reduceMotion: true)
                let renderer = ImageRenderer(content: preview.fixedSize())
                renderer.scale = Tokens.Size.renderScale
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else { throw RenderError.noImage(name) }
                try png.write(to: directory.appendingPathComponent(name), options: .atomic)
                count += 1
            }
        }
        return count
    }
}
