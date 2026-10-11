// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Independent D0 card; never a numbered candidate or an activating window.
final class RoarkTTranslationPanel: NSPanel {
  private let row = TranslationRow(frame: .zero)
  var onActivate: (() -> Void)?

  init() {
    super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    hidesOnDeactivate = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    contentView = row
    row.onActivate = { [weak self] in self?.onActivate?() }
    setAccessibilityLabel("候选翻译区")
  }
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  func show(_ state: RoarkTCandidateTranslationSession, beside parent: NSPanel) {
    guard state.ticket != nil, parent.isVisible else { orderOut(nil); return }
    appearance = parent.appearance
    level = parent.level
    row.ready = state.commit != nil
    row.retry = state.canRetry
    row.title = state.isLoading ? "翻译中" : (state.failure != nil ? "不可用" : "候选翻译")
    // The session may retain the last translation while a new ticket loads.
    // It is never displayed for another candidate, even during the debounce interval.
    row.text = state.isLoading ? "正在翻译…" : state.displayText
    row.toolTip = state.commit?.text ?? state.failure
    row.setAccessibilityLabel("\(row.title)：\(row.text)")
    row.setAccessibilityHelp(row.retry ? "点击或按 Tab 重试" : row.ready ? "点击或按 Tab 上屏" : "继续输入无需等待")
    let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
    setFrame(RoarkTPanelDesign.place(size: NSSize(width: parent.frame.width, height: 60), caret: parent.frame, screen: screen), display: true)
    row.needsDisplay = true
    orderFront(nil)
  }
}

private final class TranslationRow: NSView {
  var title = ""
  var text = ""
  var ready = false
  var retry = false
  var onActivate: (() -> Void)?
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
  }
  required init?(coder: NSCoder) { nil }
  override func accessibilityPerformPress() -> Bool {
    guard ready || retry else { return false }
    onActivate?(); return true
  }
  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    _ = accessibilityPerformPress()
  }
  override func draw(_ dirtyRect: NSRect) {
    RoarkTPanelDesign.surface(bounds)
    let ink = ready ? RoarkTPanelDesign.foreground : RoarkTPanelDesign.secondary
    if let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: nil) {
      let tinted = image.copy() as! NSImage
      tinted.lockFocus()
      (ready ? RoarkTPanelDesign.accent : RoarkTPanelDesign.secondary).set()
      NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
      tinted.unlockFocus()
      tinted.draw(in: NSRect(x: 12, y: 22, width: 16, height: 16))
    }
    let textWidth = max(0, bounds.width - 36 - 12 - ((ready || retry) ? 38 : 0))
    RoarkTPanelDesign.text(title, in: NSRect(x: 36, y: 12, width: textWidth, height: 14), size: 11, color: RoarkTPanelDesign.secondary)
    RoarkTPanelDesign.text(text, in: NSRect(x: 36, y: 30, width: textWidth, height: 18), color: ink)
    if ready || retry {
      let rect = NSRect(x: bounds.width - 42, y: 20, width: 30, height: 20)
      RoarkTPanelDesign.line.setStroke()
      let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
      path.lineWidth = 0.5; path.stroke()
      RoarkTPanelDesign.text("Tab", in: rect.insetBy(dx: 5, dy: 3), size: 11, color: RoarkTPanelDesign.secondary)
    }
  }
}
