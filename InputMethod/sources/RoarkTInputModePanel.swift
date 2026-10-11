// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import InputMethodKit
import QuartzCore

/// Transient D0 caret badge; never takes focus or accepts keyboard input.
final class RoarkTInputModePanel: NSPanel {
  private let badge = ModeBadgeView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
  private var dismissal: Timer?
  private weak var inputClient: IMKTextInput?
  private var lastAscii: Bool?
  private var presentation = 0

  init() {
    super.init(
      contentRect: badge.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    contentView = badge
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    ignoresMouseEvents = true
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    isReleasedWhenClosed = false
  }
  static func showsLegacyStatus(for optionName: String) -> Bool { optionName != "ascii_mode" }
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
  func activate(client: IMKTextInput?, ascii: Bool) {
    inputClient = client
    lastAscii = nil
    update(ascii: ascii)
  }
  func deactivate() {
    inputClient = nil
    hide()
  }
  func update(ascii: Bool) {
    guard let client = inputClient, lastAscii != ascii else { return }
    lastAscii = ascii
    var caret = NSRect.zero
    let index = client.selectedRange().location
    client.attributes(
      forCharacterIndex: index == NSNotFound ? 0 : index, lineHeightRectangle: &caret)
    show(ascii: ascii, caret: caret)
  }
  func show(ascii: Bool, caret: NSRect) {
    hide()
    guard caret.origin.x.isFinite, caret.origin.y.isFinite, caret.height > 0,
      let screen = NSScreen.screens.first(where: { $0.frame.intersects(caret) })
    else { return }
    badge.ascii = ascii
    appearance = NSApp.effectiveAppearance
    setFrame(
      RoarkTPanelDesign.place(
        size: NSSize(width: 48, height: 48), caret: caret, screen: screen.visibleFrame),
      display: true)
    let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    alphaValue = animate ? 0 : 1
    orderFrontRegardless()
    // Tokens.Motion.appear: 140 ms, cubic (0.2, 0.8, 0.2, 1).
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animate ? 0.14 : 0
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
      animator().alphaValue = 1
    }
    dismissal = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.dismiss() }
    }
  }
  private func dismiss() {
    let current = presentation
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.08  // Motion.disappear
      context.timingFunction = CAMediaTimingFunction(name: .linear)
      animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.presentation == current else { return }
        self.hide()
      }
    }
  }
  func hide() {
    presentation += 1
    dismissal?.invalidate()
    dismissal = nil
    // Explicit hide (focus change/typing) is immediate; no stale animated badge.
    orderOut(nil)
    alphaValue = 1
  }
}

private final class ModeBadgeView: NSView {
  var ascii = false {
    didSet {
      setAccessibilityLabel(ascii ? "英文输入" : "中文输入")
      needsDisplay = true
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    RoarkTPanelDesign.surface(bounds)
    RoarkTPanelDesign.accentSoft.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 10, yRadius: 10).fill()
    let text = NSAttributedString(
      string: ascii ? "英" : "中",
      attributes: [
        .font: NSFont.systemFont(ofSize: 17, weight: .semibold),  // Typography.input
        .foregroundColor: RoarkTPanelDesign.accent,
      ])
    let size = text.size()
    text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
  }
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("中文输入")
  }
  required init?(coder: NSCoder) { nil }
}
