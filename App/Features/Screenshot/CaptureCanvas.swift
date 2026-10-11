import AppKit
import SwiftUI
import QuartzCore
import RoarkTCore
import RoarkTPlatform
import os

@MainActor final class CaptureCanvas: NSView {
    let image: CGImage
    var selection = CGRect.zero { didSet { notice = nil; updateSelectionLayers() } }
    var onCancel: () -> Void = {}
    var onPreview: (CGImage) -> Void = { _ in }
    var onComplete: (CGImage) -> Void = { _ in }
    var onSave: (CGImage) -> Void = { _ in }
    var onRestore: () -> Void = {}
    var allowed: () -> Bool = { SecureInput.status() == .allowed }
    private var notice: String?
    private enum Output { case copy, save, preview }
    private let windows: [CGRect]
    private var hoveredWindow: CGRect? { didSet { updateSelectionLayers() } }
    private var clickWindow: CGRect?
    private var freeSelecting = false
    private var didDrag = false
    private var tracking: NSTrackingArea?
    private var anchor = CGPoint.zero
    private var original = CGRect.zero
    private var handle: ScreenshotHandle?
    private var moving = false
    private var tool: ScreenshotEditorModel.Tool?
    private var history = ScreenshotAnnotationHistory()
    private var draft: ScreenshotAnnotation?
    private let frozenLayer = CALayer()
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let labelLayer = CATextLayer()
    private let annotationClip = CAShapeLayer()
    private var annotationView: CaptureAnnotationView!
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval?
    private var frameTotal: CFTimeInterval = 0
    private var frameCount = 0
    private var dragging = false
    private static let timing = Logger(subsystem: Identifiers.appBundleID, category: "ScreenshotTiming")
    private var toolbar: NSHostingView<CaptureToolbar>?
    private var textField: NSTextField?
    private var textPoint = CGPoint.zero
    private func complete(_ output: Output = .copy) {
        guard allowed() else { onCancel(); return }
        commitText()
        guard let result = ScreenshotCompositor.render(image: image, size: bounds.size, selection: selection, annotations: history.items) else { return }
        switch output {
        case .copy: onComplete(result)
        case .save: onSave(result)
        case .preview: onPreview(result)
        }
    }
    private func updateToolbar() {
        guard !selection.isEmpty else { toolbar?.isHidden = true; return }
        let root = CaptureToolbar(tool: tool, canUndo: !history.items.isEmpty, canRedo: !history.undone.isEmpty,
            select: { [weak self] in self?.commitText(); self?.tool = $0; self?.updateToolbar() },
            undo: { [weak self] in self?.history.undo(); self?.updateAnnotations(); self?.updateToolbar() },
            redo: { [weak self] in self?.history.redo(); self?.updateAnnotations(); self?.updateToolbar() },
            cancel: { [weak self] in self?.onCancel() }, complete: { [weak self] in self?.complete() }, preview: { [weak self] in self?.complete(.preview) })
        let view: NSHostingView<CaptureToolbar>
        if let toolbar { view = toolbar; view.rootView = root }
        else { view = NSHostingView(rootView: root); addSubview(view); toolbar = view }
        view.isHidden = false
        let width = min(bounds.width - 16, Tokens.Screenshot.toolbarWidth)
        view.frame = CGRect(x: min(max(8, selection.maxX - width), bounds.width - width - 8),
                            y: min(max(8, selection.maxY + 12), bounds.height - 56), width: width, height: 48)

    }
    private func commitText() {
        guard let field = textField else { return }
        if !field.stringValue.isEmpty {
            history.append(ScreenshotAnnotation(tool: .text, points: [textPoint], text: field.stringValue))
        }
        field.removeFromSuperview(); textField = nil; updateAnnotations()
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage, windows: [CGRect] = []) {
        self.image = image; self.windows = windows; super.init(frame: frame)
        wantsLayer = true
        frozenLayer.frame = bounds; frozenLayer.contents = image
        frozenLayer.contentsGravity = .resize
        layer?.addSublayer(frozenLayer)
        annotationView = CaptureAnnotationView(frame: bounds, image: image)
        annotationView.wantsLayer = true
        annotationView.layer?.mask = annotationClip
        addSubview(annotationView)
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.black.withAlphaComponent(0.48).cgColor
        borderLayer.fillColor = nil; borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
        borderLayer.lineWidth = Tokens.Screenshot.selectionStroke
        handlesLayer.fillColor = NSColor.white.cgColor
        labelLayer.fontSize = 13; labelLayer.foregroundColor = NSColor.white.cgColor
        labelLayer.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        for overlay in [maskLayer, borderLayer, handlesLayer, labelLayer] { layer?.addSublayer(overlay) }
        updateSelectionLayers()
        setAccessibilityLabel("截图：拖动框选，单击选窗口，方向键微调，↩ 或 ⌘C 复制，⇧↩ 保存并复制路径，R 恢复上次选区，Esc 取消")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate(); displayLink = nil
        labelLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
    private func updateAnnotations() {
        annotationView.items = history.items + (draft.map { [$0] } ?? [])
        annotationView.needsDisplay = true
    }
    private func updateSelectionLayers() {
        guard annotationView != nil else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let visible = selection.isEmpty ? (hoveredWindow ?? .zero) : selection
        let mask = CGMutablePath(); mask.addRect(bounds)
        if !visible.isEmpty { mask.addRect(visible) }
        maskLayer.path = mask
        borderLayer.path = visible.isEmpty ? nil : CGPath(rect: visible, transform: nil)
        annotationClip.frame = bounds
        annotationClip.path = CGPath(rect: selection, transform: nil)
        let handles = CGMutablePath()
        if !selection.isEmpty {
            for h in ScreenshotHandle.allCases {
                let p = h.point(in: selection)
                handles.addEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            }
        }
        handlesLayer.path = handles
        labelLayer.isHidden = false
        let pixels = CaptureGeometry.pixels(visible, image: image, size: bounds.size)
        labelLayer.string = notice ?? (selection.isEmpty
            ? "单击选窗口 · 拖动框选 · R 恢复上次选区 · Esc 取消"
            : "\(Int(pixels.width)) × \(Int(pixels.height)) · ↩/⌘C 复制 · ⇧↩ 保存路径 · R 恢复 · Esc 取消")
        labelLayer.frame = CGRect(x: max(8, min(visible.minX, bounds.width - 610)),
            y: max(8, visible.minY - 25), width: min(610, bounds.width - 16), height: 20)
        if let toolbar, !toolbar.isHidden {
            var frame = toolbar.frame
            frame.origin = CGPoint(x: min(max(8, selection.maxX - frame.width), bounds.width - frame.width - 8),
                y: min(max(8, selection.maxY + 12), bounds.height - 56))
            toolbar.frame = frame
        }
    }
    @objc private func recordFrame(_ link: CADisplayLink) {
        guard dragging else { return }
        if let lastFrame { frameTotal += link.timestamp - lastFrame; frameCount += 1 }
        lastFrame = link.timestamp
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    func updateHover(at point: CGPoint) {
        guard selection.isEmpty, !dragging else { return }
        hoveredWindow = windows.first { $0.contains(point) }
    }
    override func mouseMoved(with event: NSEvent) { updateHover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { if !dragging { hoveredWindow = nil } }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        commitText()
        dragging = true; lastFrame = nil; frameTotal = 0; frameCount = 0
        displayLink?.invalidate()
        displayLink = displayLink(target: self, selector: #selector(recordFrame(_:)))
        displayLink?.add(to: .main, forMode: .common)
        anchor = convert(event.locationInWindow, from: nil); original = selection
        didDrag = false; freeSelecting = false; clickWindow = windows.first { $0.contains(anchor) }
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
        if handle == nil && !moving {
            selection = .zero; freeSelecting = true
            hoveredWindow = clickWindow; toolbar?.isHidden = true
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hypot(p.x - anchor.x, p.y - anchor.y) >= 3 { didDrag = true }
        if freeSelecting && !didDrag { return }
        if freeSelecting { hoveredWindow = nil }
        if var drawing = draft {
            let point = CGPoint(x: min(max(selection.minX, p.x), selection.maxX), y: min(max(selection.minY, p.y), selection.maxY))
            if drawing.tool == .pen { drawing.points.append(point) }
            else if drawing.tool != .number { drawing.points[drawing.points.count - 1] = point }
            draft = drawing; updateAnnotations(); return
        }
        guard tool == nil else { return }
        let delta = CGSize(width: p.x - anchor.x, height: p.y - anchor.y)
        if let handle { selection = CaptureGeometry.resized(original, handle: handle, by: delta, bounds: bounds) }
        else if moving { selection = CaptureGeometry.moved(original, by: delta, bounds: bounds) }
        else { selection = CaptureGeometry.selection(from: anchor, to: p, bounds: bounds) }
    }
    @objc private func finishText() { commitText(); window?.makeFirstResponder(self); updateToolbar() }
    override func mouseUp(with event: NSEvent) {
        if freeSelecting && !didDrag { selection = clickWindow ?? .zero }
        freeSelecting = false; clickWindow = nil
        dragging = false; displayLink?.invalidate(); displayLink = nil
        if frameCount > 0 { Self.timing.info("drag_frame_ms \(self.frameTotal * 1000 / Double(self.frameCount), privacy: .public)") }
        if let draft { history.append(draft); self.draft = nil; updateAnnotations() }
        updateToolbar()
    }
    func showNotice(_ message: String) { notice = message; updateSelectionLayers() }
    func restore(_ rect: CGRect) {
        textField?.removeFromSuperview(); textField = nil
        tool = nil; draft = nil; history = ScreenshotAnnotationHistory()
        hoveredWindow = nil
        selection = CaptureGeometry.restored(rect, bounds: bounds)
        updateAnnotations(); updateToolbar()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // The field editor owns copy/undo while entering a text annotation.
        guard textField == nil else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
            complete(); return true
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { history.redo() } else { history.undo() }
            updateAnnotations(); updateToolbar(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel(); return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 36 || event.keyCode == 76, modifiers.isEmpty || modifiers == .shift {
            complete(modifiers == .shift ? .save : .copy); return
        }
        if modifiers.isEmpty, event.charactersIgnoringModifiers?.lowercased() == "r" {
            guard allowed() else { onCancel(); return }
            onRestore(); return
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
        selection = CaptureGeometry.moved(selection, by: delta, bounds: bounds); updateToolbar()
    }
}

/// The annotation surface is invalidated only by edits; changing the crop only updates its layer mask.
@MainActor private final class CaptureAnnotationView: NSView {
    let image: CGImage
    var items: [ScreenshotAnnotation] = []
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    init(frame: CGRect, image: CGImage) { self.image = image; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for item in items { ScreenshotCompositor.draw(item, image: image, size: bounds.size, context: context) }
    }
}
