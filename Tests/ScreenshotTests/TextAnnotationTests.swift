import AppKit
import SwiftUI
import RoarkTCore
import XCTest
@testable import RoarkTApp

final class TextAnnotationTests: XCTestCase {
    @MainActor func testEditorAndExportShareTypographyAndLayout() throws {
        let annotation = ScreenshotAnnotation(tool: .text, points: [CGPoint(x: 15, y: 20)],
            text: "Synthetic 中文\n第二行", color: .systemBlue, width: 4, textMaxWidth: 160)
        let editor = CaptureTextView(annotation: annotation, availableSize: CGSize(width: 160, height: 200))
        let export = ScreenshotTextLayout(annotation: annotation)
        let attributes = export.storage.attributes(at: 0, effectiveRange: nil)
        let editorAttributes = try XCTUnwrap(editor.textStorage).attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(editor.font, attributes[.font] as? NSFont)
        XCTAssertEqual(editor.font?.pointSize, 17)
        XCTAssertEqual(editor.typingAttributes[.foregroundColor] as? NSColor, attributes[.foregroundColor] as? NSColor)
        XCTAssertEqual(editorAttributes[.font] as? NSFont, attributes[.font] as? NSFont)
        XCTAssertEqual(editorAttributes[.foregroundColor] as? NSColor, annotation.color)
        XCTAssertEqual(editorAttributes[.paragraphStyle] as? NSParagraphStyle, attributes[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertFalse(editor.drawsBackground)
        XCTAssertEqual(editor.focusRingType, .none)
        XCTAssertEqual(editor.textContainerOrigin, CGPoint(x: 2, y: 2))
        XCTAssertEqual(editor.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(editor.textContainer?.containerSize.width, 156)
        let manager = try XCTUnwrap(editor.layoutManager)
        let container = try XCTUnwrap(editor.textContainer)
        manager.ensureLayout(for: container)
        export.manager.ensureLayout(for: export.container)
        XCTAssertEqual(manager.usedRect(for: container), export.manager.usedRect(for: export.container))
        for glyph in 0..<manager.numberOfGlyphs {
            XCTAssertEqual(manager.location(forGlyphAt: glyph), export.manager.location(forGlyphAt: glyph))
        }
    }

    @MainActor func testNativeMarkedTextNewlineAndAutomaticGrowth() throws {
        for background in [false, true] {
            let annotation = ScreenshotAnnotation(tool: .text, points: [.zero], textMaxWidth: 220, textBackground: background)
            let editor = CaptureTextView(annotation: annotation, availableSize: CGSize(width: 220, height: 240))
            let emptySize = editor.frame.size
            editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(editor.string, "中文")
            XCTAssertGreaterThan(editor.frame.width, emptySize.width)
            editor.insertText("中文输入", replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertFalse(editor.hasMarkedText())
            XCTAssertEqual(editor.string, "中文输入")
            let lineSize = editor.frame.size
            editor.insertNewline(nil)
            editor.insertText("second line", replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(editor.string, "中文输入\nsecond line")
            XCTAssertGreaterThan(editor.frame.height, lineSize.height)
            XCTAssertGreaterThan(editor.frame.width, lineSize.width)
            editor.insertText(String(repeating: "长句", count: 25), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertLessThanOrEqual(editor.frame.width, 220)
            XCTAssertGreaterThan(editor.frame.height, lineSize.height * 2)
        }
    }

    func testEmptyTextDiscardAndReplacementUndoRedo() {
        var history = ScreenshotAnnotationHistory()
        for text in ["", " \n\t"] {
            history.commitText(.init(tool: .text, points: [.zero], text: text), replacing: nil)
        }
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertFalse(history.canUndo)
        let original = ScreenshotAnnotation(tool: .text, points: [.zero], text: "before")
        history.append(original)
        var edited = original; edited.text = "after\nnewline"
        history.commitText(edited, replacing: 0)
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items[0].text, edited.text)
        history.undo(); XCTAssertEqual(history.items[0].text, "before")
        history.redo(); XCTAssertEqual(history.items[0].text, edited.text)
        edited.text = ""
        history.commitText(edited, replacing: 0)
        XCTAssertTrue(history.items.isEmpty)
        history.undo(); XCTAssertEqual(history.items[0].text, "after\nnewline")
    }

    @MainActor func testBackgroundToggleAppliesToTypingAndRestoresOnReeditAndUndo() throws {
        let canvas = try canvas()
        try click(canvas)
        try editor(canvas).insertText("清晰的标注", replacementRange: NSRange(location: NSNotFound, length: 0))
        var style = try toolbar(canvas).style
        style.textBackground = true; style.colorHex = "202124"
        try toolbar(canvas).changeStyle(style)
        XCTAssertEqual(canvas.annotations.count, 1)
        XCTAssertTrue(canvas.annotations[0].textBackground)
        XCTAssertEqual(canvas.annotations[0].text, "清晰的标注")
        try toolbar(canvas).undo()
        XCTAssertFalse(canvas.annotations[0].textBackground)
        try toolbar(canvas).redo()
        XCTAssertTrue(canvas.annotations[0].textBackground)
        try click(canvas, at: CGPoint(x: 48, y: 50), count: 2)
        let editing = try editor(canvas)
        XCTAssertTrue(editing.annotation.textBackground)
        XCTAssertEqual(editing.textColor, .white)
        XCTAssertEqual(editing.insertionPointColor, .white)
        XCTAssertTrue(try toolbar(canvas).style.textBackground == true)
        editing.insertText("继续", replacementRange: NSRange(location: NSNotFound, length: 0))
        var expected = editing.annotation; expected.text = editing.string
        var output: CGImage?
        canvas.roundedCorners = false
        canvas.onComplete = { output = $0 }
        try toolbar(canvas).complete()
        let exported = try XCTUnwrap(ScreenshotCompositor.render(image: canvas.image, size: canvas.bounds.size,
            selection: canvas.selection, annotations: [expected]))
        XCTAssertEqual(NSBitmapImageRep(cgImage: try XCTUnwrap(output)).representation(using: .png, properties: [:]),
                       NSBitmapImageRep(cgImage: exported).representation(using: .png, properties: [:]))
    }

    func testBackgroundPreferenceDecodesMissingFieldAndRoundTrips() throws {
        let old = try JSONDecoder().decode(ScreenshotAnnotationStyle.self, from: Data(#"{"colorHex":"D84A2F","width":17}"#.utf8))
        XCTAssertNotEqual(old.textBackground, true)
        let enabled = ScreenshotAnnotationStyle(colorHex: "202124", width: 24, textBackground: true)
        XCTAssertEqual(try JSONDecoder().decode(ScreenshotAnnotationStyle.self, from: JSONEncoder().encode(enabled)), enabled)
    }

    @MainActor private func canvas() throws -> CaptureCanvas {
        let context = try XCTUnwrap(CGContext(data: nil, width: 420, height: 300, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 420, height: 300))
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 420, height: 300), image: try XCTUnwrap(context.makeImage()))
        canvas.allowed = { true }
        canvas.restore(CGRect(x: 20, y: 20, width: 360, height: 220))
        try toolbar(canvas).select(.text)
        return canvas
    }
    @MainActor private func toolbar(_ canvas: CaptureCanvas) throws -> CaptureToolbar {
        try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSHostingView<CaptureToolbar> }.first).rootView
    }
    @MainActor private func click(_ canvas: CaptureCanvas, at point: CGPoint = CGPoint(x: 45, y: 45), count: Int = 1) throws {
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1))
        canvas.mouseDown(with: down)
        canvas.mouseUp(with: down)
    }
    @MainActor private func editor(_ canvas: CaptureCanvas) throws -> CaptureTextView {
        try XCTUnwrap(canvas.subviews.compactMap { $0 as? CaptureTextView }.first)
    }

    @MainActor func testEscapePassesThroughMonitorAndCommitsWithoutCancellingCapture() throws {
        let canvas = try canvas()
        try click(canvas)
        let editor = try editor(canvas)
        editor.insertText("留下文字", replacementRange: NSRange(location: NSNotFound, length: 0))
        var cancels = 0
        canvas.onCancel = { cancels += 1 }
        let panel = CapturePanel(captureRect: canvas.bounds)
        panel.contentView = canvas
        defer { panel.contentView = nil; panel.close() }
        XCTAssertTrue(panel.makeFirstResponder(editor))
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        let coordinator = ScreenshotCoordinator(allowed: { true })
        XCTAssertNotNil(coordinator.routeCanvasEvent(escape))
        editor.cancelOperation(nil)
        XCTAssertFalse(canvas.isEditingText)
        XCTAssertEqual(cancels, 0)
        try click(canvas, at: CGPoint(x: 47, y: 48), count: 2)
        XCTAssertEqual(try self.editor(canvas).string, "留下文字")
        canvas.keyDown(with: escape)
        XCTAssertEqual(cancels, 0)
        canvas.keyDown(with: escape)
        XCTAssertEqual(cancels, 1)
    }

    @MainActor func testClickToolSwitchAndCompleteCommitWithoutDuplicateText() throws {
        let canvas = try canvas()
        try click(canvas)
        XCTAssertEqual(try editor(canvas).frame.origin, CGPoint(x: 45, y: 45))
        try editor(canvas).insertText("old", replacementRange: NSRange(location: NSNotFound, length: 0))
        try click(canvas, at: CGPoint(x: 240, y: 100))
        XCTAssertEqual(try editor(canvas).string, "")
        try toolbar(canvas).select(.rectangle) // Empty second annotation is discarded.
        XCTAssertFalse(canvas.isEditingText)
        try click(canvas, at: CGPoint(x: 47, y: 48), count: 2)
        let editing = try editor(canvas)
        XCTAssertEqual(editing.string, "old")
        editing.setSelectedRange(NSRange(location: 0, length: 3))
        editing.insertText("new\n中文", replacementRange: NSRange(location: NSNotFound, length: 0))
        var expected = editing.annotation; expected.text = editing.string
        var image: CGImage?
        canvas.onComplete = { image = $0 }
        try toolbar(canvas).complete()
        XCTAssertFalse(canvas.isEditingText)
        let actual = try XCTUnwrap(image)
        let rectangular = try XCTUnwrap(ScreenshotCompositor.render(image: canvas.image, size: canvas.bounds.size,
            selection: canvas.selection, annotations: [expected]))
        let composed = try XCTUnwrap(ScreenshotExport.render(image: rectangular, pointSize: canvas.selection.size, roundedCorners: true))
        XCTAssertEqual(NSBitmapImageRep(cgImage: actual).representation(using: .png, properties: [:]),
            NSBitmapImageRep(cgImage: composed).representation(using: .png, properties: [:]))
    }
}
