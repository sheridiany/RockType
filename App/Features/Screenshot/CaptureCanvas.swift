import AppKit
import SwiftUI

@MainActor final class CaptureCanvas: NSView {
    let image: CGImage
    var selection = CGRect.zero
    var onCancel: () -> Void = {}
    var onPreview: (CGImage) -> Void = { _ in }
    var onComplete: (CGImage) -> Void = { _ in }
    private var anchor = CGPoint.zero
    private var original = CGRect.zero
    private var handle: ScreenshotHandle?
    private var moving = false
    private var tool: ScreenshotEditorModel.Tool?
    private var history = ScreenshotAnnotationHistory()
    private var draft: ScreenshotAnnotation?
    private var toolbar: NSHostingView<CaptureToolbar>?
    private var textField: NSTextField?
    private var textPoint = CGPoint.zero
    private func complete(preview: Bool = false) {
        commitText()
        guard let result = ScreenshotCompositor.render(image: image, size: bounds.size, selection: selection, annotations: history.items) else { return }
        if preview { onPreview(result) } else { onComplete(result) }
    }
    private func updateToolbar() {
        toolbar?.removeFromSuperview(); toolbar = nil
        guard !selection.isEmpty else { return }
        let view = NSHostingView(rootView: CaptureToolbar(tool: tool, canUndo: !history.items.isEmpty, canRedo: !history.undone.isEmpty,
            select: { [weak self] in self?.commitText(); self?.tool = $0; self?.updateToolbar() },
            undo: { [weak self] in self?.history.undo(); self?.needsDisplay = true; self?.updateToolbar() },
            redo: { [weak self] in self?.history.redo(); self?.needsDisplay = true; self?.updateToolbar() },
            cancel: { [weak self] in self?.onCancel() }, complete: { [weak self] in self?.complete() }, preview: { [weak self] in self?.complete(preview: true) }))
        let width = min(bounds.width - 16, Tokens.Screenshot.toolbarWidth)
        view.frame = CGRect(x: min(max(8, selection.maxX - width), bounds.width - width - 8),
                            y: min(max(8, selection.maxY + 12), bounds.height - 56), width: width, height: 48)
        addSubview(view); toolbar = view
    }
    private func commitText() {
        guard let field = textField else { return }
        if !field.stringValue.isEmpty {
            history.append(ScreenshotAnnotation(tool: .text, points: [textPoint], text: field.stringValue))
        }
        field.removeFromSuperview(); textField = nil; needsDisplay = true
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage) {
        self.image = image; super.init(frame: frame)
        setAccessibilityLabel("截图框选：拖动框选，手柄调整，方向键微调，Enter 完成，Escape 取消")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        if !selection.isEmpty, let rendered = ScreenshotCompositor.render(image: image, size: bounds.size,
            selection: selection, annotations: history.items + (draft.map { [$0] } ?? [])) {
            NSImage(cgImage: rendered, size: selection.size).draw(in: selection, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        }
        let mask = NSBezierPath(rect: bounds)
        if !selection.isEmpty { mask.appendRect(selection) }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill(); mask.fill()
        guard !selection.isEmpty else { return }
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selection); border.lineWidth = Tokens.Screenshot.selectionStroke; border.stroke()
        for h in ScreenshotHandle.allCases {
            let p = h.point(in: selection)
            NSColor.white.setFill(); NSBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)).fill()
        }
        let pixels = CaptureGeometry.pixels(selection, image: image, size: bounds.size)
        let label = "\(Int(pixels.width)) × \(Int(pixels.height)) · ↩ 完成 · Esc 取消"
        label.draw(at: CGPoint(x: max(8, min(selection.minX, bounds.width - 300)), y: max(8, selection.minY - 25)),
                   withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white,
                                    .backgroundColor: NSColor.black.withAlphaComponent(0.7)])
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        commitText()
        anchor = convert(event.locationInWindow, from: nil); original = selection
        if let tool, selection.contains(anchor) {
            if tool == .text {
                textPoint = anchor
                let field = NSTextField(frame: CGRect(x: anchor.x, y: anchor.y, width: min(240, bounds.maxX - anchor.x), height: 28))
                field.placeholderString = "输入标注，Enter 确认"; field.target = self; field.action = #selector(finishText)
                addSubview(field); textField = field; window?.makeFirstResponder(field)
            } else {
                draft = ScreenshotAnnotation(tool: tool, points: [anchor, anchor], number: history.items.filter { $0.tool == .number }.count + 1)
            }
            return
        }
        if tool != nil { return }
        handle = ScreenshotHandle.allCases.first { h in
            let p = h.point(in: selection)
            return !selection.isEmpty && hypot(p.x - anchor.x, p.y - anchor.y) <= 9
        }
        moving = handle == nil && selection.contains(anchor)
        if handle == nil && !moving { selection = .zero }
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if var drawing = draft {
            let point = CGPoint(x: min(max(selection.minX, p.x), selection.maxX), y: min(max(selection.minY, p.y), selection.maxY))
            if drawing.tool == .pen { drawing.points.append(point) }
            else if drawing.tool != .number { drawing.points[drawing.points.count - 1] = point }
            draft = drawing; needsDisplay = true; return
        }
        guard tool == nil else { return }
        let delta = CGSize(width: p.x - anchor.x, height: p.y - anchor.y)
        if let handle { selection = CaptureGeometry.resized(original, handle: handle, by: delta, bounds: bounds) }
        else if moving { selection = CaptureGeometry.moved(original, by: delta, bounds: bounds) }
        else { selection = CaptureGeometry.selection(from: anchor, to: p, bounds: bounds) }
        needsDisplay = true
    }
    @objc private func finishText() { commitText(); window?.makeFirstResponder(self); updateToolbar() }
    override func mouseUp(with event: NSEvent) {
        if let draft { history.append(draft); self.draft = nil }
        updateToolbar(); needsDisplay = true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { history.redo() } else { history.undo() }
            needsDisplay = true; updateToolbar(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel(); return }
        if event.keyCode == 36, !selection.isEmpty {
            complete()
            return
        }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let delta: CGSize
        switch event.keyCode {
        case 123: delta = CGSize(width: -step, height: 0)
        case 124: delta = CGSize(width: step, height: 0)
        case 125: delta = CGSize(width: 0, height: step)
        case 126: delta = CGSize(width: 0, height: -step)
        default: super.keyDown(with: event); return
        }
        selection = CaptureGeometry.moved(selection, by: delta, bounds: bounds); needsDisplay = true; updateToolbar()
    }
}
