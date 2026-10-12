import AppKit

/// One source for the editor, hit testing, on-canvas drawing and pixel export.
enum ScreenshotText {
    static func attributes(for annotation: ScreenshotAnnotation) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
            .foregroundColor: foreground(for: annotation), .paragraphStyle: paragraph]
        if !annotation.textBackground {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 1
            shadow.shadowOffset = CGSize(width: 0, height: -0.5)
            attributes[.shadow] = shadow
        }
        return attributes
    }

    static func foreground(for annotation: ScreenshotAnnotation) -> NSColor {
        guard annotation.textBackground else { return annotation.color }
        let rgb = annotation.color.usingColorSpace(.sRGB) ?? .black
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? .black : .white
    }

    static func inset(for annotation: ScreenshotAnnotation) -> CGSize {
        annotation.textBackground ? CGSize(width: 6, height: 4) : CGSize(width: 2, height: 2)
    }

    static func isEmpty(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Both NSTextView and the compositor use TextKit 1, with identical container geometry.
final class ScreenshotTextLayout {
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    let container: NSTextContainer
    let annotation: ScreenshotAnnotation
    let inset: CGSize

    init(annotation: ScreenshotAnnotation) {
        self.annotation = annotation
        inset = ScreenshotText.inset(for: annotation)
        storage = NSTextStorage(string: annotation.text, attributes: ScreenshotText.attributes(for: annotation))
        container = NSTextContainer(size: CGSize(width: max(1, (annotation.textMaxWidth ?? .greatestFiniteMagnitude) - inset.width * 2),
                                                 height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        manager.usesFontLeading = true
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
    }

    var size: CGSize {
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let extra = manager.extraLineFragmentTextContainer === container ? manager.extraLineFragmentRect : .zero
        return CGSize(width: min(annotation.textMaxWidth ?? .greatestFiniteMagnitude, ceil(used.maxX) + inset.width * 2),
                      height: ceil(max(used.maxY, extra.maxY)) + inset.height * 2)
    }

    func drawBackground(at point: CGPoint) {
        guard annotation.textBackground else { return }
        let rect = CGRect(origin: point, size: size)
        annotation.color.withAlphaComponent(1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
    }

    func draw(at point: CGPoint) {
        drawBackground(at: point)
        let origin = CGPoint(x: point.x + inset.width, y: point.y + inset.height)
        let range = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: range, at: origin)
        manager.drawGlyphs(forGlyphRange: range, at: origin)
    }
}

/// Native IME composition stays in NSTextView; only the shared annotation background is painted.
@MainActor final class CaptureTextView: NSTextView {
    let annotation: ScreenshotAnnotation
    private let textLayout: ScreenshotTextLayout
    private let availableSize: CGSize
    var onCommit: () -> Void = {}

    init(annotation: ScreenshotAnnotation, availableSize: CGSize) {
        self.annotation = annotation
        self.availableSize = availableSize
        textLayout = ScreenshotTextLayout(annotation: annotation)
        super.init(frame: CGRect(origin: annotation.points.first ?? .zero, size: .zero), textContainer: textLayout.container)
        isRichText = false
        importsGraphics = false
        drawsBackground = false
        backgroundColor = .clear
        focusRingType = .none
        textContainerInset = textLayout.inset
        isHorizontallyResizable = false
        isVerticallyResizable = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        let attributes = ScreenshotText.attributes(for: annotation)
        font = attributes[.font] as? NSFont
        textColor = ScreenshotText.foreground(for: annotation)
        insertionPointColor = ScreenshotText.foreground(for: annotation)
        defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        typingAttributes = attributes
        setAccessibilityLabel("截图文字标注")
        setAccessibilityHelp("Enter 换行，Esc 结束编辑，点击别处提交")
        resizeToContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didChangeText() {
        super.didChangeText()
        // Do not replace attributed contents here: doing so destroys marked text and IME selection.
        resizeToContent()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        textLayout.drawBackground(at: .zero)
        super.draw(dirtyRect)
    }

    private func resizeToContent() {
        let measured = textLayout.size
        let lineHeight = layoutManager?.defaultLineHeight(for: font ?? .systemFont(ofSize: 16)) ?? 20
        // Leave room for the caret; keep the layout container width fixed so wrapping also matches export.
        setFrameSize(CGSize(width: min(availableSize.width, max(2, measured.width)),
                            height: min(availableSize.height, max(lineHeight + textLayout.inset.height * 2, measured.height))))
    }

    override func cancelOperation(_ sender: Any?) { onCommit() }
}
