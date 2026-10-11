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
    var onOCRCopy: (CGImage) -> Void = { _ in }
    var onPreview: (CGImage) -> Void = { _ in }
    var onComplete: (CGImage) -> Void = { _ in }
    var onSave: (CGImage) -> Void = { _ in }
    var onSaveAs: (CGImage) -> Void = { _ in }
    var onCopyColor: (String) throws -> Void = { try ScreenshotOutput.shared.copyColor($0) }
    var roundedCorners = true
    private let magnifier = CaptureMagnifier(frame: .zero)
    private var pointer: CGPoint?
    private(set) var sampledColor: String?
    private var sampledPixel: CGPoint?
    private func updateMagnifier(at point: CGPoint) {
        pointer = point
        guard allowed(), !isEditingText, tool == nil, bounds.contains(point),
              toolbar?.isHidden != false || toolbar?.frame.contains(point) != true else {
            hideMagnifier(); return
        }
        let pixel = CGPoint(x: floor(point.x * CGFloat(image.width) / bounds.width),
                            y: floor(point.y * CGFloat(image.height) / bounds.height))
        if sampledPixel != pixel {
            magnifier.sample = CapturePixelSampler.sample(image: image, point: point, size: bounds.size)
            sampledPixel = pixel; sampledColor = magnifier.sample?.hex
        }
        magnifier.frame = CapturePixelSampler.frame(near: point, bounds: bounds,
            avoiding: toolbar?.isHidden == false ? toolbar?.frame : nil)
        magnifier.isHidden = magnifier.sample == nil
    }
    private func hideMagnifier() {
        magnifier.isHidden = true; magnifier.sample = nil; sampledPixel = nil; sampledColor = nil
    }
    private func copyColor() {
        guard allowed(), let pointer, bounds.contains(pointer) else { return }
        guard let sample = CapturePixelSampler.sample(image: image, point: pointer, size: bounds.size) else { return }
        do { try onCopyColor(sample.hex); showNotice("颜色已复制") }
        catch { showNotice("无法复制颜色，请重试。") }
    }
    var onPin: (CGImage) -> Void = { _ in }
    var onRestore: () -> Void = {}
    var allowed: () -> Bool = { ScreenCapture.isReadable }
    private var notice: String?
    private enum Output { case copy, save, saveAs, preview, pin, ocrCopy }
    private var smartSelection: CaptureSmartSelection
    private var hierarchyScroll: CGFloat = 0
    private var hoveredWindow: CGRect? { didSet { updateSelectionLayers() } }
    private var clickWindow: CGRect?
    private var freeSelecting = false
    private var didDrag = false
    private var tracking: NSTrackingArea?
    private var anchor = CGPoint.zero
    private var original = CGRect.zero
    private var handle: ScreenshotHandle?
    private var moving = false
    private var tool: ScreenshotTool?
    var toolStyles: [String: ScreenshotAnnotationStyle] = [:]
    var onStyleChange: (ScreenshotTool, ScreenshotAnnotationStyle) -> Void = { _, _ in }
    private var scrollRemainder: CGFloat = 0
    private var activeStyle: ScreenshotAnnotationStyle {
        if let index = selectedAnnotation, history.items.indices.contains(index) {
            let item = history.items[index]
            let color = item.color.usingColorSpace(.sRGB) ?? item.color
            return .init(colorHex: String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded())),
                width: item.tool == .text ? item.fontSize : item.width)
        }
        return (tool ?? .rectangle).style(from: toolStyles)
    }
    private func setStyle(_ style: ScreenshotAnnotationStyle) {
        guard let tool, tool != .eraser else { return }
        toolStyles[tool.rawValue] = style
        let sanitized = tool.style(from: toolStyles)
        toolStyles[tool.rawValue] = sanitized; onStyleChange(tool, sanitized)
        if let index = selectedAnnotation, history.items.indices.contains(index) {
            var item = history.items[index]
            item.color = sanitized.nsColor
            if item.tool == .text { item.fontSize = sanitized.width } else { item.width = sanitized.width }
            history.replace(at: index, with: item); updateAnnotations()
        }
        updateToolbar()
    }
    private func annotation(tool: ScreenshotTool, at point: CGPoint) -> ScreenshotAnnotation {
        let style = tool.style(from: toolStyles)
        return ScreenshotAnnotation(tool: tool, points: [point, point], color: style.nsColor,
                                    width: tool == .text ? 5 : style.width, fontSize: tool == .text ? style.width : 17)
    }
    override func scrollWheel(with event: NSEvent) {
        guard allowed(), textEditor == nil else { return }
        if selection.isEmpty, tool == nil {
            hierarchyScroll += event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 12 : 1)
            let integral = hierarchyScroll.rounded(.towardZero)
            hierarchyScroll -= integral
            let steps = Int(max(-12, min(12, integral)))
            for _ in 0..<min(12, abs(steps)) { cycleElement(parent: steps > 0) }
            return
        }
        guard let tool, tool != .eraser else { return }
        scrollRemainder += event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 12 : 1)
        let steps = scrollRemainder.rounded(.towardZero)
        guard steps != 0 else { return }
        scrollRemainder -= steps
        var style = activeStyle; style.width += steps; setStyle(style)
    }
    private var history = ScreenshotAnnotationHistory()
    private var draft: ScreenshotAnnotation?
    private(set) var selectedAnnotation: Int?
    private var annotationOriginal: ScreenshotAnnotation?
    private var annotationHandle: ScreenshotHandle?
    private var annotationChanged = false
    var annotations: [ScreenshotAnnotation] { history.items }

    func selectTool(_ value: ScreenshotTool?) {
        finishTextEditing(); tool = value; selectedAnnotation = nil; scrollRemainder = 0
        if value != nil { hideMagnifier() }
        updateAnnotations(); updateToolbar()
        window?.makeFirstResponder(self)
    }
    private func undoAnnotation(redo: Bool = false) {
        finishTextEditing()
        if redo { history.redo() } else { history.undo() }
        selectedAnnotation = nil; updateAnnotations(); updateToolbar()
    }
    private func deleteSelectedAnnotation() {
        guard let index = selectedAnnotation else { return }
        history.remove(at: index); selectedAnnotation = nil
        updateAnnotations(); updateToolbar()
    }
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
    private var textEditor: CaptureTextView?
    private var editingTextIndex: Int?
    var isEditingText: Bool { textEditor != nil }
    private func complete(_ output: Output = .copy) {
        guard allowed() else { onCancel(); return }
        finishTextEditing()
        guard let composed = ScreenshotCompositor.render(image: image, size: bounds.size, selection: selection, annotations: history.items) else { return }
        // OCR needs every edge pixel. Other outputs share the same rounded appearance.
        let crop = CaptureGeometry.pixels(selection, image: image, size: bounds.size)
        let pointSize = CGSize(width: crop.width * bounds.width / CGFloat(image.width), height: crop.height * bounds.height / CGFloat(image.height))
        guard let result = ScreenshotExport.render(image: composed, pointSize: pointSize,
            roundedCorners: roundedCorners && output != .ocrCopy) else { return }
        switch output {
        case .copy: onComplete(result)
        case .save: onSave(result)
        case .saveAs: onSaveAs(result)
        case .preview: onPreview(result)
        case .ocrCopy: onOCRCopy(result)
        case .pin: onPin(result)
        }
    }
    private func updateToolbar() {
        guard !selection.isEmpty else { toolbar?.isHidden = true; return }
        let root = CaptureToolbar(tool: tool, style: activeStyle,
            changeStyle: { [weak self] in self?.setStyle($0) }, canUndo: history.canUndo, canRedo: history.canRedo,
            select: { [weak self] in self?.selectTool($0) },
            undo: { [weak self] in self?.undoAnnotation() },
            redo: { [weak self] in self?.undoAnnotation(redo: true) },
            cancel: { [weak self] in self?.onCancel() }, complete: { [weak self] in self?.complete() }, preview: { [weak self] in self?.complete(.preview) })
        let view: NSHostingView<CaptureToolbar>
        if let toolbar { view = toolbar; view.rootView = root }
        else { view = NSHostingView(rootView: root); addSubview(view); toolbar = view }
        view.isHidden = false
        view.frame = CaptureGeometry.toolbarFrame(selection: selection, bounds: bounds)
        if let pointer { updateMagnifier(at: pointer) }

    }
    @discardableResult func finishTextEditing() -> Bool {
        guard let editor = textEditor else { return false }
        guard allowed() else {
            discardTextEditor(); onCancel(); return true
        }
        editor.unmarkText()
        var annotation = editor.annotation
        annotation.text = editor.string
        history.commitText(annotation, replacing: editingTextIndex)
        discardTextEditor()
        updateAnnotations(); updateSelectionLayers(); updateToolbar()
        return true
    }
    private func discardTextEditor() {
        guard let editor = textEditor else { return }
        textEditor = nil; editingTextIndex = nil
        editor.onCommit = {}
        if window?.firstResponder === editor { window?.makeFirstResponder(self) }
        editor.removeFromSuperview()
    }
    func finishTextEditingIfOutside(_ event: NSEvent) {
        guard let editor = textEditor else { return }
        if event.window === window, editor.bounds.contains(editor.convert(event.locationInWindow, from: nil)) { return }
        finishTextEditing()
    }
    private func beginTextEditing(at point: CGPoint, replacing index: Int? = nil) {
        guard allowed() else { onCancel(); return }
        var annotation = index.map { history.items[$0] } ?? self.annotation(tool: .text, at: point)
        let origin = annotation.points.first ?? point
        let available = CGSize(width: max(1, selection.maxX - origin.x), height: max(1, selection.maxY - origin.y))
        annotation.textMaxWidth = min(annotation.textMaxWidth ?? available.width, available.width)
        let editor = CaptureTextView(annotation: annotation, availableSize: available)
        editingTextIndex = index; textEditor = editor; hideMagnifier()
        editor.onCommit = { [weak self] in self?.finishTextEditing() }
        addSubview(editor)
        updateAnnotations(); updateSelectionLayers()
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    }
    /// AppKit can replace a layer-backed view's root when it is attached/reconfigured.
    /// Reattach our persistent layers every time; never rely on the root created during init.
    override func makeBackingLayer() -> CALayer {
        let backing = super.makeBackingLayer()
        for item in [frozenLayer, maskLayer, borderLayer, handlesLayer, labelLayer] {
            backing.addSublayer(item)
        }
        return backing
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage, windows: [CGRect] = []) {
        self.image = image
        self.smartSelection = CaptureSmartSelection(windows: windows)
        super.init(frame: frame)
        wantsLayer = true
        frozenLayer.frame = bounds; frozenLayer.contents = image
        frozenLayer.contentsGravity = .resize
        annotationView = CaptureAnnotationView(frame: bounds, image: image)
        annotationView.isHidden = true
        annotationView.wantsLayer = true
        annotationView.layer?.mask = annotationClip
        addSubview(annotationView)
        magnifier.isHidden = true; magnifier.wantsLayer = true; addSubview(magnifier)
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.black.withAlphaComponent(0.48).cgColor
        borderLayer.fillColor = nil; borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
        borderLayer.lineWidth = Tokens.Screenshot.selectionStroke
        handlesLayer.fillColor = NSColor.white.cgColor
        labelLayer.fontSize = 13; labelLayer.foregroundColor = NSColor.white.cgColor
        labelLayer.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        updateSelectionLayers()
        setAccessibilityLabel("截图：拖动框选，单击选窗口，双击选区或 ↩ 复制，C 复制颜色，⇧C 复制 OCR，⌘S 另存为，⌥方向键调整左上边，⌘方向键调整右下边，⇧↩ 保存路径，R 恢复，P 贴图，Esc 取消")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate(); displayLink = nil
        labelLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
    override func layout() {
        super.layout()
        updateSelectionLayers()
    }
    private func updateAnnotations() {
        annotationView.items = history.items.enumerated().compactMap { index, annotation in
            if index == editingTextIndex { return nil }
            if index == selectedAnnotation && annotationOriginal != nil { return draft }
            return annotation
        } + (annotationOriginal == nil ? (draft.map { [$0] } ?? []) : [])
        annotationView.selectedBounds = selectedAnnotation.flatMap { index in
            guard history.items.indices.contains(index) else { return nil }
            return (annotationOriginal != nil ? draft : history.items[index])?.bounds
        }
        annotationView.isHidden = annotationView.items.isEmpty && annotationView.selectedBounds == nil
        annotationView.needsDisplay = !annotationView.isHidden
    }
    private func updateSelectionLayers() {
        guard annotationView != nil else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        frozenLayer.frame = bounds
        annotationView.frame = bounds
        // Give the compositor real drawable bounds; render(in:) alone can still paint
        // paths outside a zero-sized layer and therefore misses this geometry error.
        for shape in [maskLayer, borderLayer, handlesLayer] { shape.frame = bounds }
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
        labelLayer.string = notice ?? (isEditingText ? "↩ 换行 · Esc 结束文字编辑 · 点击别处提交" : selection.isEmpty
            ? "单击选元素/窗口 · 滚轮/Tab 扩大 · ⇧Tab 缩小 · 拖动框选 · C 取色 · Esc 取消"
            : "\(Int(pixels.width)) × \(Int(pixels.height)) · 双击/↩ 复制 · ⌘S 另存 · ⇧C OCR · ⌥ 左/上边 · ⌘ 右/下边")
        labelLayer.frame = CGRect(x: max(8, min(visible.minX, bounds.width - 670)),
            y: max(8, visible.minY - 25), width: min(670, bounds.width - 16), height: 20)
        if let toolbar, !toolbar.isHidden {
            toolbar.frame = CaptureGeometry.toolbarFrame(selection: selection, bounds: bounds)
            if let pointer { updateMagnifier(at: pointer) }
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
        updateMagnifier(at: point)
        guard selection.isEmpty, !dragging else { return }
        smartSelection.update(at: point)
        if hoveredWindow != smartSelection.current { hoveredWindow = smartSelection.current }
    }
    func installElements(_ snapshot: CaptureAccessibility.Snapshot) {
        guard !dragging, selection.isEmpty else { return }
        smartSelection.install(snapshot)
        if let pointer { updateHover(at: pointer) }
    }
    var hoveredSelection: CGRect? { hoveredWindow }
    private func cycleElement(parent: Bool) {
        guard selection.isEmpty, !dragging else { return }
        smartSelection.cycle(parent: parent)
        if hoveredWindow != smartSelection.current { hoveredWindow = smartSelection.current }
    }
    override func mouseMoved(with event: NSEvent) { updateHover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) {
        // Color/selection keys follow the display under the pointer, without interrupting native text input.
        if !(NSApp?.keyWindow?.firstResponder is CaptureTextView) {
            window?.makeKey(); window?.makeFirstResponder(self)
        }
        mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) { hideMagnifier(); pointer = nil; if !dragging { hoveredWindow = nil } }
    override func mouseDown(with event: NSEvent) {
        guard allowed() else { onCancel(); return }
        finishTextEditing()
        window?.makeKey(); window?.makeFirstResponder(self)
        anchor = convert(event.locationInWindow, from: nil); original = selection
        updateMagnifier(at: anchor)
        annotationOriginal = nil; annotationHandle = nil; annotationChanged = false
        didDrag = false; freeSelecting = false
        smartSelection.update(at: anchor); clickWindow = smartSelection.current
        if selection.contains(anchor) {
            if tool != .eraser, event.clickCount >= 2, let index = CaptureHitTesting.text(at: anchor, items: history.items, selection: selection) {
                selectedAnnotation = nil; beginTextEditing(at: anchor, replacing: index); return
            }
            if let index = selectedAnnotation, history.items.indices.contains(index) {
                annotationHandle = CaptureHitTesting.handle(at: anchor, rect: history.items[index].bounds, radius: 8)
            }
            // Option permits a new overlapping stroke without selecting the annotation underneath.
            let hit = event.modifierFlags.contains(.option) && tool != nil && tool != .eraser ? nil
                : annotationHandle != nil ? selectedAnnotation : CaptureHitTesting.annotation(at: anchor, items: history.items)
            if event.clickCount == 2, tool == nil, hit == nil, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                complete(); return
            }
            if let index = hit {
                if tool == .eraser { history.remove(at: index); selectedAnnotation = nil; updateAnnotations(); updateToolbar(); return }
                selectedAnnotation = index; annotationOriginal = history.items[index]; tool = history.items[index].tool
                draft = history.items[index]; dragging = true; hideMagnifier(); updateAnnotations(); updateToolbar(); return
            }
            selectedAnnotation = nil; updateAnnotations()
            if tool == .eraser { return }
            if tool == .text { beginTextEditing(at: anchor); return }
        }
        dragging = true; lastFrame = nil; frameTotal = 0; frameCount = 0
        displayLink?.invalidate()
        displayLink = displayLink(target: self, selector: #selector(recordFrame(_:)))
        displayLink?.add(to: .main, forMode: .common)
        if let tool, selection.contains(anchor) {
            draft = annotation(tool: tool, at: anchor)
            draft?.number = (history.items.filter { $0.tool == .number }.map(\.number).max() ?? 0) + 1
            return
        }
        if tool != nil { return }
        handle = CaptureHitTesting.handle(at: anchor, rect: selection, radius: 9)
        moving = handle == nil && selection.contains(anchor)
        if handle == nil && !moving {
            selection = .zero; freeSelecting = true
            hoveredWindow = clickWindow; toolbar?.isHidden = true
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard allowed() else { onCancel(); return }
        guard dragging, textEditor == nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        updateMagnifier(at: p)
        if hypot(p.x - anchor.x, p.y - anchor.y) >= 3 { didDrag = true }
        if freeSelecting && !didDrag { return }
        if freeSelecting { hoveredWindow = nil }
        if let original = annotationOriginal, selectedAnnotation != nil {
            let delta = CGSize(width: p.x - anchor.x, height: p.y - anchor.y)
            if let annotationHandle {
                draft = original.resized(to: CaptureGeometry.resized(original.bounds, handle: annotationHandle, by: delta, bounds: selection))
            } else {
                let target = CaptureGeometry.moved(original.bounds, by: delta, bounds: selection)
                draft = original.moved(by: CGSize(width: target.minX - original.bounds.minX, height: target.minY - original.bounds.minY))
            }
            annotationChanged = didDrag; updateAnnotations(); return
        }
        if var drawing = draft {
            var point = CGPoint(x: min(max(selection.minX, p.x), selection.maxX), y: min(max(selection.minY, p.y), selection.maxY))
            if event.modifierFlags.contains(.shift) {
                point = ScreenshotAnnotation.constrainedEnd(from: anchor, to: point, tool: drawing.tool, within: selection)
            }
            if drawing.tool == .pen || drawing.tool == .highlighter { drawing.points.append(point) }
            else if drawing.tool != .number { drawing.points[drawing.points.count - 1] = point }
            draft = drawing; updateAnnotations(); return
        }
        guard tool == nil else { return }
        let delta = CGSize(width: p.x - anchor.x, height: p.y - anchor.y)
        if let handle { selection = CaptureGeometry.resized(original, handle: handle, by: delta, bounds: bounds) }
        else if moving { selection = CaptureGeometry.moved(original, by: delta, bounds: bounds) }
        else { selection = CaptureGeometry.selection(from: anchor, to: p, bounds: bounds) }
    }
    override func mouseUp(with event: NSEvent) {
        if freeSelecting && !didDrag { selection = clickWindow ?? .zero }
        freeSelecting = false; clickWindow = nil
        dragging = false; displayLink?.invalidate(); displayLink = nil
        if frameCount > 0 { Self.timing.info("drag_frame_ms \(self.frameTotal * 1000 / Double(self.frameCount), privacy: .public)") }
        if let draft {
            if annotationOriginal != nil, let index = selectedAnnotation {
                if annotationChanged { history.replace(at: index, with: draft) }
            } else if ![ScreenshotTool.rectangle, .ellipse, .mosaic, .arrow, .line].contains(draft.tool)
                        || draft.points.first != draft.points.last {
                history.append(draft)
            }
            self.draft = nil; annotationOriginal = nil; updateAnnotations()
        }
        updateToolbar()
    }
    func showNotice(_ message: String) { notice = message; updateSelectionLayers() }
    func restore(_ rect: CGRect) {
        discardTextEditor()
        selectedAnnotation = nil; annotationOriginal = nil
        tool = nil; draft = nil; history = ScreenshotAnnotationHistory()
        hoveredWindow = nil
        selection = CaptureGeometry.restored(rect, bounds: bounds)
        updateAnnotations(); updateToolbar()
    }
    private func command(for event: NSEvent) -> CaptureKeyCommand? {
        let command = CaptureKeyboard.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
        if case .hierarchy = command, !selection.isEmpty { return nil }
        return command
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isEditingText, event.modifierFlags.contains(.command), let command = command(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        execute(command); return true
    }
    override func keyDown(with event: NSEvent) {
        if isEditingText {
            if event.keyCode == 53 { finishTextEditing() } else { super.keyDown(with: event) }
            return
        }
        guard let command = command(for: event) else { super.keyDown(with: event); return }
        execute(command)
    }
    private func execute(_ command: CaptureKeyCommand) {
        guard allowed() else { hideMagnifier(); onCancel(); return }
        switch command {
        case .cancel: onCancel()
        case .copy: complete()
        case .quickSave: complete(.save)
        case .saveAs: complete(.saveAs)
        case .pin: complete(.pin)
        case .ocrCopy: complete(.ocrCopy)
        case .copyColor: copyColor()
        case .restore: onRestore()
        case .hierarchy(let parent): cycleElement(parent: parent)
        case .undo: undoAnnotation()
        case .redo: undoAnnotation(redo: true)
        case .delete: deleteSelectedAnnotation()
        case .tool(let value): selectTool(value)
        case let .nudge(direction, edge, fast): nudge(direction, edge: edge, step: fast ? 10 : 1)
        }
    }
    private func nudge(_ direction: CaptureDirection, edge: CaptureEdge?, step: CGFloat) {
        if let edge {
            selection = CaptureGeometry.nudged(selection, direction: direction, edge: edge, step: step, bounds: bounds)
        } else if let index = selectedAnnotation, history.items.indices.contains(index) {
            let item = history.items[index]
            let target = CaptureGeometry.moved(item.bounds, by: direction.delta(step: step), bounds: selection)
            history.replace(at: index, with: item.moved(by: CGSize(width: target.minX - item.bounds.minX, height: target.minY - item.bounds.minY)))
            updateAnnotations()
        } else { selection = CaptureGeometry.moved(selection, by: direction.delta(step: step), bounds: bounds) }
        updateToolbar()
    }

}
