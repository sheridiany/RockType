import AppKit
import SwiftUI

/// I1: one macOS 14-compatible symbol vocabulary for capture, preview and pinned images.
/// Introduction versions were checked against Apple's CoreGlyphs name_availability catalog.
enum ScreenshotSymbols {
    static let select = "arrow.up.left" // macOS 10.15
    static let roundedRectangle = "app" // macOS 10.15
    static let rectangle = "rectangle" // macOS 10.15
    static let ellipse = "circle" // macOS 10.15
    static let arrow = "arrow.up.right" // macOS 10.15
    static let line = "line.diagonal" // macOS 11.0
    static let pen = "pencil.tip" // macOS 10.15
    static let highlighter = "highlighter" // macOS 11.0
    static let mosaic = "checkerboard.rectangle" // macOS 11.0
    static let text = "textformat" // macOS 10.15
    static let number = "1.circle" // macOS 10.15
    static let eraser = "eraser" // macOS 13.0
    static let undo = "arrow.uturn.left" // macOS 10.15
    static let redo = "arrow.uturn.right" // macOS 10.15
    static let ocr = "text.viewfinder" // macOS 12.0
    static let cancel = "xmark" // macOS 10.15
    static let complete = "checkmark" // macOS 10.15
    static let pin = "pin.fill" // macOS 10.15
    static let save = "square.and.arrow.down.fill" // macOS 10.15
    static let history = "clock.arrow.circlepath" // macOS 11.0
    static let stack = "square.stack.fill" // macOS 10.15
    static let photo = "photo.fill" // macOS 10.15
    static let translate = "character.book.closed.fill" // macOS 11.0
    static let codes = "qrcode.viewfinder" // macOS 10.15
    static let warning = "exclamationmark.triangle.fill" // macOS 10.15
    static let info = "info.square.fill" // macOS 13.0
    static let recognizedText = "text.alignleft" // macOS 10.15
    static let send = "paperplane.fill" // macOS 10.15
    static let imageAI = "viewfinder" // macOS 10.15
    static let images = "photo.on.rectangle" // macOS 10.15
    static let clipboard = "doc.on.clipboard.fill" // macOS 10.15
    static let scroll = "rectangle.expand.vertical" // macOS 10.15
    static let selection = "viewfinder" // macOS 10.15
    static let desktopApple = "apple.logo" // macOS 13.0
    static let desktopNetwork = "wifi" // macOS 10.15
    static let desktopBattery = "battery.100percent" // macOS 14.0
    static let document = "doc.text.fill" // macOS 10.15
    static let sidebar = "sidebar.left" // macOS 10.15
    static let folder = "folder.fill" // macOS 10.15
    static let edit = "square.and.pencil" // macOS 10.15
    static let archive = "archivebox.fill" // macOS 10.15
    static let checked = "checkmark.square.fill" // macOS 10.15
    static let richText = "doc.richtext.fill" // macOS 11.0
    static let desktopGrid = "square.grid.2x2.fill" // macOS 10.15
    static let desktopBrowser = "safari.fill" // macOS 10.15
    static let notes = "note.text" // macOS 11.0
    static let terminal = "terminal.fill" // macOS 11.0
    static let delete = "trash.fill" // macOS 10.15
    static let protected = "lock.shield.fill" // macOS 10.15
    static let copy = "doc.on.doc.fill" // macOS 10.15
    static let lock = "lock.fill" // macOS 10.15
    static let passthrough = "cursorarrow" // macOS 11.0
    static let opacity = "circle.lefthalf.filled" // macOS 12.0
    static let next = "arrow.right" // macOS 10.15
    static let previous = "arrow.left" // macOS 10.15
    static let hide = "eye.slash.fill" // macOS 10.15
    static let show = "eye.fill" // macOS 10.15
    static let settings = "slider.horizontal.3" // macOS 10.15
    static let all: [String] = [
        select,
        roundedRectangle,
        rectangle,
        ellipse,
        arrow,
        line,
        pen,
        highlighter,
        mosaic,
        text,
        number,
        eraser,
        undo,
        redo,
        ocr,
        cancel,
        complete,
        pin,
        save,
        history,
        stack,
        photo,
        translate,
        codes,
        warning,
        info,
        recognizedText,
        send,
        imageAI,
        images,
        clipboard,
        scroll,
        selection,
        desktopApple,
        desktopNetwork,
        desktopBattery,
        document,
        sidebar,
        folder,
        edit,
        archive,
        checked,
        richText,
        desktopGrid,
        desktopBrowser,
        notes,
        terminal,
        delete,
        protected,
        copy,
        lock,
        passthrough,
        opacity,
        next,
        previous,
        hide,
        show,
        settings,
    ]
    static let pointSize: CGFloat = 14
    static func image(_ name: String, description: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: name == mosaic ? .regular : .medium))
    }
}

struct ScreenshotIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName).font(.system(size: ScreenshotSymbols.pointSize, weight: systemName == ScreenshotSymbols.mosaic ? .regular : .medium))
            .symbolRenderingMode(.monochrome).frame(width: 18, height: 18).accessibilityHidden(true)
    }
}
struct ScreenshotLabel: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View { Label { Text(title) } icon: { ScreenshotIcon(systemName: systemImage) } }
}

/// Fixed geometry only for icon controls; text actions keep room for their accessible label.
struct ScreenshotIconButtonStyle: ButtonStyle {
    var selected = false
    var primary = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        let p = Tokens.palette(scheme)
        let foreground = primary ? p.onAccent : selected ? p.card : p.foreground
        let background = primary ? p.accent : selected ? p.foreground : hovering || configuration.isPressed ? p.hover : .clear
        configuration.label.frame(width: 32, height: 30)
            .foregroundStyle(enabled ? foreground : p.tertiary)
            .background(enabled ? background : p.cardSecondary, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(focused ? p.focus : .clear, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle()).onHover { hovering = $0 }
    }
}
