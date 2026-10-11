import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Bounded, explicit input only. Neither clipboard polling nor file copies are used.
enum ScreenshotImageImport {
    static let maximumBytes = 40 * 1024 * 1024
    static let maximumPixels = 64_000_000
    enum Failure: Error { case invalidImage, tooLarge, unsupportedFile }
    static func decode(_ data: Data) throws -> CGImage {
        try Task.checkCancellation()
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw Failure.invalidImage }
        guard width <= maximumPixels / height else { throw Failure.tooLarge }
        // Applies EXIF orientation while retaining the full original pixel dimensions.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw Failure.invalidImage }
        try Task.checkCancellation()
        return image
    }
    static func read(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw Failure.unsupportedFile }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw Failure.unsupportedFile }
        guard let size = values.fileSize, size <= maximumBytes else { throw Failure.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        return data
    }
    @MainActor static func type(for provider: NSItemProvider) -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return UTType.fileURL.identifier }
        return provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
    }
}
