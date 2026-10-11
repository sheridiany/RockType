import AppKit
import RoarkTPlatform

/// Point-size geometry, independent of the image's pixel resolution.
enum PinnedImageGeometry {
    static func scale(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite else { return 1 }
        return min(4, max(0.1, proposed))
    }

    static func fitted(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let factor = min(1, bounds.width / rect.width, bounds.height / rect.height)
        let size = CGSize(width: rect.width * factor, height: rect.height * factor)
        return CGRect(x: min(max(rect.minX, bounds.minX), bounds.maxX - size.width),
                      y: min(max(rect.minY, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func zoom(_ frame: CGRect, base: CGSize, scale: CGFloat, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: base.width * self.scale(scale), height: base.height * self.scale(scale))
        return fitted(CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                             width: size.width, height: size.height), in: bounds)
    }
}

/// Only closed pins are retained, newest last. No serialization or image-derived titles.
struct PinnedImageHistory {
    struct Entry {
        let image: CGImage
        let frame: CGRect
        let opacity: CGFloat
        let locked: Bool
        var bytes: Int { image.bytesPerRow * image.height }
    }
    private(set) var limit: Int
    let byteLimit: Int
    private(set) var entries: [Entry] = []
    init(limit: Int = 10, byteLimit: Int = 64 * 1024 * 1024) {
        self.limit = max(0, limit); self.byteLimit = max(0, byteLimit)
    }
    mutating func append(_ entry: Entry) {
        guard limit > 0, entry.bytes <= byteLimit else { return }
        entries.append(entry)
        while entries.count > limit || entries.reduce(0, { $0 + $1.bytes }) > byteLimit { entries.removeFirst() }
    }
    mutating func setLimit(_ value: Int) {
        limit = min(50, max(0, value))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }
    mutating func removeLast() { if !entries.isEmpty { entries.removeLast() } }
    mutating func clear() { entries.removeAll() }
}

enum PinnedImageAction { case save, ocr, copyText, translate, translateImage, barcodes }

/// Owns the escape hatch as long as any pin or recent image exists.
@MainActor final class PinnedImageController: NSObject, NSWindowDelegate {
    static let shared = PinnedImageController()
    private(set) var panels: [NSPanel] = []
    private(set) var history = PinnedImageHistory()
    var onAction: (CGImage, PinnedImageAction) -> Void = { _, _ in }
    private let allowed: () -> Bool
    private let copyImage: (CGImage) throws -> Void
    private let present: (NSPanel) -> Void
    private let showsMenu: Bool
    private var statusItem: NSStatusItem?
    private var protectionTask: Task<Void, Never>?
    private var discarding = false
    private(set) var allHidden = false
    private weak var focused: NSPanel?
    private let show: (NSPanel) -> Void

    init(allowed: @escaping () -> Bool = { SecureInput.status() == .allowed },
         copyImage: @escaping (CGImage) throws -> Void = { try ScreenshotOutput.shared.copyImage($0) },
         showsMenu: Bool = true,
         show: @escaping (NSPanel) -> Void = { $0.orderFrontRegardless() },
         present: @escaping (NSPanel) -> Void = { panel in
             panel.orderFrontRegardless(); panel.makeKey(); panel.makeFirstResponder(panel.contentView)
         }) {
        self.show = show
        self.allowed = allowed; self.copyImage = copyImage
        self.showsMenu = showsMenu; self.present = present
    }

    /// Global AppKit points, bottom-left origin. Output pixels remain untouched.
    @discardableResult func pin(_ image: CGImage, at rect: CGRect) -> Bool {
        guard allowed(), rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width > 0, rect.height > 0,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) ?? NSScreen.main else { return false }
        let frame = PinnedImageGeometry.fitted(rect, in: screen.visibleFrame)
        let panel = PinnedImagePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self
        let view = PinnedImageView(image: image, baseSize: frame.size, allowed: allowed, copyImage: copyImage)
        view.controller = self
        panel.contentView = view
        if allHidden { showAll() }
        panels.append(panel); focused = panel
        updateMenu(); present(panel); startProtection()
        return true
    }

    /// Privacy clearing and shutdown must never populate the recent list.
    func closeAll() {
        discarding = true; allHidden = false; focused = nil
        for panel in panels { panel.close() }
        history.clear(); discarding = false
        protectionTask?.cancel(); protectionTask = nil
        updateMenu()
    }

    @objc func toggleAll() {
        guard allowed() else { closeAll(); return }
        if allHidden { showAll() }
        else if !panels.isEmpty { allHidden = true; panels.forEach { $0.orderOut(nil) }; updateMenu() }
    }
    func showAll() {
        guard allowed() else { closeAll(); return }
        allHidden = false; panels.forEach(show); updateMenu()
    }
    @objc func closeGroup() {
        guard allowed() else { closeAll(); return }
        allHidden = false; focused = nil
        for panel in panels { panel.close() }
        updateMenu()
    }
    @objc func focusNext() {
        guard allowed(), !panels.isEmpty else { if !allowed() { closeAll() }; return }
        if allHidden { showAll() }
        let current = panels.firstIndex(where: { $0.isKeyWindow }) ?? panels.firstIndex(where: { $0 === focused })
        let next = panels[((current ?? -1) + 1) % panels.count]
        next.ignoresMouseEvents = false; focused = next; present(next); updateMenu()
    }
    func windowDidBecomeKey(_ notification: Notification) {
        if let panel = notification.object as? NSPanel, panels.contains(where: { $0 === panel }) { focused = panel }
    }

    @discardableResult func restoreLast() -> Bool {
        guard allowed(), let entry = history.entries.last, pin(entry.image, at: entry.frame),
              let panel = panels.last, let view = panel.contentView as? PinnedImageView else { return false }
        history.removeLast()
        panel.alphaValue = entry.opacity
        view.locked = entry.locked
        // Restoring always makes the pin interactive, even if it used to pass clicks through.
        panel.ignoresMouseEvents = false
        updateMenu()
        return true
    }

    func setHistoryLimit(_ value: Int) {
        history.setLimit(value)
        updateMenu()
        if panels.isEmpty && history.entries.isEmpty { protectionTask?.cancel(); protectionTask = nil }
    }

    @objc private func restoreFromMenu() { _ = restoreLast() }
    @objc func exitMousePassthrough() {
        guard allowed() else { closeAll(); return }
        for panel in panels { panel.ignoresMouseEvents = false }
        updateMenu()
    }
    @objc private func clearFromMenu() { closeAll() }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              panels.contains(where: { $0 === panel }) else { return }
        if !discarding, allowed(), let view = panel.contentView as? PinnedImageView {
            history.append(.init(image: view.image, frame: panel.frame, opacity: panel.alphaValue, locked: view.locked))
        }
        panel.contentView = nil
        panels.removeAll { $0 === panel }
        if panels.isEmpty { allHidden = false; focused = nil }
        updateMenu()
        if panels.isEmpty && history.entries.isEmpty { protectionTask?.cancel(); protectionTask = nil }
    }

    func updateMenu() {
        guard showsMenu else { return }
        if panels.isEmpty && history.entries.isEmpty {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem); self.statusItem = nil }
            return
        }
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "贴图")
            statusItem?.button?.toolTip = "贴图 · 恢复最近关闭 / 退出鼠标穿透"
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let info = NSMenuItem(title: "贴图 \(panels.count) 张 · 最近关闭 \(history.entries.count) 张", action: nil, keyEquivalent: "")
        info.isEnabled = false; menu.addItem(info)
        let restore = NSMenuItem(title: "恢复最近关闭的贴图", action: #selector(restoreFromMenu), keyEquivalent: "z")
        restore.keyEquivalentModifierMask = [.command, .shift]; restore.target = self
        restore.isEnabled = !history.entries.isEmpty; menu.addItem(restore)
        let exit = NSMenuItem(title: "退出全部鼠标穿透", action: #selector(exitMousePassthrough), keyEquivalent: "")
        exit.target = self; exit.isEnabled = panels.contains(where: \.ignoresMouseEvents); menu.addItem(exit)
        for (title, selector) in [(allHidden ? "显示全部贴图" : "隐藏全部贴图", #selector(toggleAll)),
                                   ("下一张贴图", #selector(focusNext)), ("关闭全部贴图", #selector(closeGroup))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; item.isEnabled = !panels.isEmpty; menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "关闭全部并清除贴图记录", action: #selector(clearFromMenu), keyEquivalent: "")
        clear.target = self; menu.addItem(clear)
        let hint = NSMenuItem(title: "最近最多 10 张 · 仅本次运行 · 总计 64 MB", action: nil, keyEquivalent: "")
        hint.isEnabled = false; menu.addItem(hint)
        statusItem?.menu = menu
    }

    private func startProtection() {
        guard protectionTask == nil else { return }
        protectionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self else { return }
                if !self.allowed() { self.closeAll(); return }
            }
        }
    }
    isolated deinit {
        protectionTask?.cancel()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

private final class PinnedImagePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class PinnedImageView: NSView {
    let image: CGImage
    private let baseSize: CGSize
    private let allowed: () -> Bool
    private let copyImage: (CGImage) throws -> Void
    weak var controller: PinnedImageController?
    private let feedback = NSTextField(labelWithString: "")
    private var feedbackTask: Task<Void, Never>?
    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedback.stringValue = message; feedback.isHidden = false
        feedback.sizeToFit()
        feedback.frame.origin = CGPoint(x: 8, y: 8)
        feedback.frame.size.width = min(feedback.frame.width, max(0, bounds.width - 16))
        feedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.feedback.isHidden = true
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.borderColor = (locked ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }
    var locked = false {
        didSet {
            window?.isMovableByWindowBackground = !locked
            layer?.borderColor = (locked ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
    }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { !locked }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(image: CGImage, baseSize: CGSize, allowed: @escaping () -> Bool,
         copyImage: @escaping (CGImage) throws -> Void) {
        self.image = image; self.baseSize = baseSize; self.allowed = allowed; self.copyImage = copyImage
        super.init(frame: CGRect(origin: .zero, size: baseSize))
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 3
        toolTip = "拖动移动 · 滚轮缩放 · ⌥滚轮透明度 · ⇧C 复制文字 · 右键更多 · Esc 关闭 · 菜单栏贴图可恢复"
        feedback.font = .systemFont(ofSize: 12, weight: .medium)
        feedback.textColor = .labelColor; feedback.backgroundColor = .controlBackgroundColor
        feedback.drawsBackground = true; feedback.isHidden = true
        feedback.lineBreakMode = .byTruncatingTail
        addSubview(feedback)
        setAccessibilityLabel("贴图")
        setAccessibilityHelp(toolTip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        guard allowed() else { controller?.closeAll(); return }
        if event.clickCount == 2 { window?.close(); return }
        window?.makeKey(); window?.makeFirstResponder(self)
        if !locked { window?.performDrag(with: event) }
    }
    static func opacity(_ proposed: CGFloat) -> CGFloat {
        proposed.isFinite ? min(1, max(0.2, proposed)) : 1
    }
    override func scrollWheel(with event: NSEvent) {
        guard allowed() else { controller?.closeAll(); return }
        if event.modifierFlags.contains(.option) {
            let step = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)
            window?.alphaValue = Self.opacity((window?.alphaValue ?? 1) + step)
            showFeedback("透明度 \(Int((window?.alphaValue ?? 1) * 100))%")
            return
        }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)
        resize(by: exp(min(1, max(-1, delta))))
    }
    override func magnify(with event: NSEvent) { resize(by: 1 + event.magnification) }
    private func resize(by factor: CGFloat) {
        guard allowed() else { controller?.closeAll(); return }
        guard !locked, let window, let screen = window.screen else { return }
        let scale = window.frame.width / baseSize.width * factor
        window.setFrame(PinnedImageGeometry.zoom(window.frame, base: baseSize, scale: scale,
                                                in: screen.visibleFrame), display: true)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard allowed() else { controller?.closeAll(); return nil }
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector, checked: Bool = false) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; item.state = checked ? .on : .off; menu.addItem(item)
        }
        add("复制图片    ⌘C", #selector(copyPicture))
        add("另存为…", #selector(savePicture))
        add("识别文字…", #selector(recognizeText))
        add("识别并复制文字    ⇧C", #selector(copyRecognizedText))
        add("翻译…（先核对识别文字）", #selector(translateText))
        add("覆盖式图片翻译…", #selector(translatePicture))
        add("识别二维码 / 条码…", #selector(recognizeCodes))
        menu.addItem(.separator())
        add("锁定位置与大小", #selector(toggleLock), checked: locked)
        add("鼠标穿透（从菜单栏“贴图”退出）", #selector(togglePassthrough), checked: window?.ignoresMouseEvents == true)
        let opacity = NSMenuItem(title: "透明度 · ⌥滚轮", action: nil, keyEquivalent: "")
        let values = NSMenu()
        for percent in [100, 80, 60, 40, 20] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.tag = percent; item.target = self
            item.state = abs((window?.alphaValue ?? 1) - CGFloat(percent) / 100) < 0.01 ? .on : .off
            values.addItem(item)
        }
        opacity.submenu = values; menu.addItem(opacity)
        menu.addItem(.separator())
        add("恢复最近关闭    ⌘⇧Z", #selector(restoreRecent))
        add("关闭    Esc", #selector(closePicture))
        return menu
    }
    @objc private func copyPicture() {
        guard allowed() else { controller?.closeAll(); return }
        do { try copyImage(image); showFeedback("图片已复制") }
        catch { showFeedback("复制失败，请重试") }
    }
    private func action(_ action: PinnedImageAction) {
        guard allowed() else { controller?.closeAll(); return }
        controller?.onAction(image, action)
    }
    @objc private func savePicture() { action(.save) }
    @objc private func recognizeText() { action(.ocr) }
    @objc private func copyRecognizedText() { action(.copyText) }
    @objc private func translatePicture() { action(.translateImage) }
    @objc private func recognizeCodes() { action(.barcodes) }
    @objc private func translateText() { action(.translate) }
    @objc private func closePicture() { window?.close() }
    @objc private func restoreRecent() { _ = controller?.restoreLast() }
    @objc func toggleLock() {
        guard allowed() else { controller?.closeAll(); return }
        locked.toggle()
        showFeedback(locked ? "位置与大小已锁定" : "已解锁")
    }
    @objc func togglePassthrough() {
        guard allowed() else { controller?.closeAll(); return }
        window?.ignoresMouseEvents.toggle(); controller?.updateMenu()
    }
    @objc private func setOpacity(_ item: NSMenuItem) {
        guard allowed() else { controller?.closeAll(); return }
        window?.alphaValue = Self.opacity(CGFloat(item.tag) / 100)
        showFeedback("透明度 \(item.tag)%")
    }
    isolated deinit { feedbackTask?.cancel() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.close(); return }
        if !performKeyEquivalent(with: event) { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command && key == "c" { copyPicture(); return true }
        if modifiers == .shift && key == "c" { copyRecognizedText(); return true }
        if modifiers == [.command, .shift] && key == "z" { restoreRecent(); return true }
        return false
    }
}
