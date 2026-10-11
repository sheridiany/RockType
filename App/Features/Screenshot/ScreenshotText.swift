import AppKit

/// One source for the editor, hit testing, on-canvas drawing and pixel export.
enum ScreenshotText {
    static func attributes(for annotation: ScreenshotAnnotation) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: NSFont.systemFont(ofSize: annotation.fontSize),
                .foregroundColor: annotation.color, .paragraphStyle: paragraph,
                .strokeColor: NSColor.white, .strokeWidth: -3]
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

    init(annotation: ScreenshotAnnotation) {
        storage = NSTextStorage(string: annotation.text, attributes: ScreenshotText.attributes(for: annotation))
        container = NSTextContainer(size: CGSize(width: annotation.textMaxWidth ?? .greatestFiniteMagnitude,
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
        return CGSize(width: ceil(used.maxX), height: ceil(max(used.maxY, extra.maxY)))
    }

    func draw(at point: CGPoint) {
        let range = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: range, at: point)
        manager.drawGlyphs(forGlyphRange: range, at: point)
    }
}

/// Native IME composition stays in NSTextView. No field editor, border, placeholder or background.
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
        textContainerInset = .zero
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
        textColor = annotation.color
        insertionPointColor = annotation.color
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
    }

    private func resizeToContent() {
        let measured = textLayout.size
        let lineHeight = layoutManager?.defaultLineHeight(for: font ?? .systemFont(ofSize: 16)) ?? 20
        // Leave room for the caret; keep the layout container width fixed so wrapping also matches export.
        setFrameSize(CGSize(width: min(availableSize.width, max(2, measured.width + 2)),
                            height: min(availableSize.height, max(lineHeight, measured.height))))
    }

    override func cancelOperation(_ sender: Any?) { onCommit() }
}
