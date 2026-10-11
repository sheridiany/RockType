// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// D0 constants copied from App/DesignSystem/Tokens.swift and U4Primitives.swift.
/// The GPL input method does not import or link the MIT App target.
enum RoarkTPanelDesign {
  static let padding: CGFloat = 12 // Space.md
  static let gap: CGFloat = 4 // Space.xs
  static let row: CGFloat = 36 // Size.row
  static let width: CGFloat = 420 // U4.candidateWidth
  static let radius: CGFloat = 12 // Radius.window
  static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
      let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                     green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
  }
  static let canvas = color(0xfcfcfd, 0x202126)
  static let foreground = color(0x1c1c21, 0xededf1)
  static let secondary = color(0x4b4b53, 0xb9b9c1)
  static let tertiary = color(0x85858d, 0x9c9ca6)
  static let accent = color(0x4f46e5, 0xa5b4fc)
  static let accentSoft = color(0xeeedfd, 0x2b2c47)
  static let onAccent = color(0xffffff, 0x14142a)
  static let line = NSColor(name: nil) { appearance in
    (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor.white : .black).withAlphaComponent(0.07)
  }
  static func surface(_ rect: NSRect) {
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
    canvas.setFill(); path.fill()
    line.setStroke(); path.lineWidth = 0.5; path.stroke() // Size.hairline
  }
  static func text(_ value: String, in rect: NSRect, size: CGFloat = 13, color: NSColor,
                   weight: NSFont.Weight = .regular) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: color, .paragraphStyle: paragraph])
  }
  static func place(size: NSSize, caret: NSRect, screen: NSRect) -> NSRect {
    let size = NSSize(width: min(size.width, screen.width), height: min(size.height, screen.height))
    let below = caret.minY - gap - size.height
    return NSRect(x: min(max(caret.minX, screen.minX), screen.maxX - size.width),
                  y: min(max(below >= screen.minY ? below : caret.maxY + gap, screen.minY), screen.maxY - size.height),
                  width: size.width, height: size.height)
  }
}

final class SquirrelPanel: NSPanel {
  private let view = RoarkTCandidateView(frame: .zero)
  private let translationPanel = RoarkTTranslationPanel()
  var inputController: SquirrelInputController?
  var position: NSRect
  private var statusMessage = ""
  private var statusTimer: Timer?
  private var pressedIndex: Int?
  private var scrollTime = Date.distantPast
  private var scrollDelta: CGFloat = 0
  private var contextMenuClick = false
  var vertical: Bool { false }
  var linear: Bool { true }
  var inlinePreedit: Bool { false }
  var inlineCandidate: Bool { false }

  init(position: NSRect) {
    self.position = position
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    level = .init(Int(CGShieldingWindowLevel()))
    hasShadow = true
    isOpaque = false
    backgroundColor = .clear
    hidesOnDeactivate = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    contentView = view
    view.onSelect = { [weak self] index in _ = self?.inputController?.selectCandidate(index) }
  }
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  // D0 is the product appearance; schema-specific colors/layout no longer override it.
  func load(config: SquirrelConfig, forDarkMode isDark: Bool) { view.needsDisplay = true }

  func hide() {
    translationPanel.orderOut(nil)
    statusTimer?.invalidate(); statusTimer = nil
    pressedIndex = nil
    orderOut(nil)
  }

  func update(preedit: String, selRange: NSRange, caretPos: Int, candidates: [String], comments: [String],
              labels: [String], highlighted index: Int, page: Int, lastPage: Bool, update: Bool) {
    if candidates.isEmpty && preedit.isEmpty {
      if !statusMessage.isEmpty {
        view.preedit = statusMessage
        view.candidates = []
        view.statusOnly = true
        statusMessage = ""
        show()
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
          MainActor.assumeIsolated { self?.hide() }
        }
      } else if statusTimer == nil { hide() }
      return
    }
    statusTimer?.invalidate(); statusTimer = nil; statusMessage = ""
    // A newly selected candidate must never leave the previous translation visible.
    translationPanel.orderOut(nil)
    view.statusOnly = false
    view.preedit = preedit
    view.candidates = Array(candidates.prefix(5))
    view.selected = index
    view.needsDisplay = true
    show()
  }

  func updateStatus(long longMessage: String, short shortMessage: String) {
    statusMessage = longMessage.isEmpty ? shortMessage : longMessage
  }

  func updateTranslation(_ state: RoarkTCandidateTranslationSession) {
    translationPanel.onActivate = { [weak self] in self?.inputController?.performTranslationAction() }
    translationPanel.show(state, beside: self)
  }

  private func show() {
    let screen = NSScreen.screens.first { $0.frame.contains(position.origin) } ?? NSScreen.main
    guard let screen else { return }
    appearance = NSApp.effectiveAppearance
    setFrame(RoarkTPanelDesign.place(size: NSSize(width: view.statusOnly ? min(420, max(100, CGFloat(view.preedit.count) * 14 + 68)) : RoarkTPanelDesign.width, height: view.statusOnly ? 48 : 83),
                                    caret: position, screen: screen.visibleFrame), display: true)
    view.needsDisplay = true
    orderFront(nil)
  }

  override func sendEvent(_ event: NSEvent) {
    let point = view.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    let index = view.candidate(at: point)
    if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
      contextMenuClick = event.type == .leftMouseDown
      if let index, let menu = inputController?.learningMenu(for: index) {
        NSMenu.popUpContextMenu(menu, with: event, for: view)
      }
      return
    }
    switch event.type {
    case .leftMouseDown: contextMenuClick = false; pressedIndex = index
    case .leftMouseUp:
      if contextMenuClick { contextMenuClick = false; return }
      if let index, pressedIndex == index { _ = inputController?.selectCandidate(index) }
      pressedIndex = nil
    case .mouseEntered: acceptsMouseMovedEvents = true
    case .mouseExited: acceptsMouseMovedEvents = false
    case .mouseMoved:
      if let index, index != view.selected { inputController?.highlightCandidate(index) }
    case .scrollWheel:
      if scrollTime.timeIntervalSinceNow < -0.4 { scrollDelta = 0 }
      scrollTime = .now
      scrollDelta += abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
      if abs(scrollDelta) > 10 { _ = inputController?.page(up: scrollDelta > 0); scrollDelta = 0 }
    default: break
    }
    super.sendEvent(event)
  }

  // The existing preview entry point renders actual production surfaces offscreen.
  static func preview(configurationPath: String, dark: Bool) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let panel = SquirrelPanel(position: NSRect(x: 100, y: 500, width: 1, height: 20))
    panel.update(preedit: "ni hao", selRange: .empty, caretPos: 6, candidates: ["你好", "你", "拟好", "妮", "呢"],
                 comments: [], labels: [], highlighted: 0, page: 0, lastPage: false, update: true)
    var state = RoarkTCandidateTranslationSession()
    let request = state.observe(.init(rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole"))!
    state.receive("Hello", for: request, direction: "zh-en")
    panel.updateTranslation(state)
    // Optional destination is a directory, supplied by the rendering test harness.
    if let output = ProcessInfo.processInfo.environment["ROARKT_PREVIEW_OUTPUT"] {
      for (name, window) in [("candidate", panel as NSPanel), ("translation", panel.translationPanel as NSPanel)] {
        if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
          view.cacheDisplay(in: view.bounds, to: bitmap)
          if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
          }
        }
      }
      panel.hide()
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { panel.hide(); Foundation.exit(EXIT_SUCCESS) }
    app.run()
  }
}

private final class RoarkTCandidateView: NSView {
  var onSelect: ((Int) -> Void)?
  var preedit = ""
  var candidates: [String] = []
  var selected = 0
  var statusOnly = false
  private var tracking: NSTrackingArea?
override var isFlipped: Bool { true }
override func isAccessibilityElement() -> Bool { true }
override func accessibilityRole() -> NSAccessibility.Role? { .group }
override func accessibilityLabel() -> String? { statusOnly ? preedit : "候选，" + preedit }
override func accessibilityChildren() -> [Any]? {
  candidateRects.enumerated().map { index, rect in
    let element = CandidateAccessibilityElement()
    element.setAccessibilityParent(self)
    element.setAccessibilityRole(.button)
    element.setAccessibilityLabel("候选 \(index + 1)，\(candidates[index])")
    element.setAccessibilitySelected(index == selected)
    element.setAccessibilityFrame(window?.convertToScreen(convert(rect, to: nil)) ?? .zero)
    element.press = { [weak self] in self?.onSelect?(index) }
    return element
  }
}
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved], owner: self)
    addTrackingArea(tracking!)
  }
  private var candidateRects: [NSRect] {
    let available = max(0, bounds.width - 24 - CGFloat(max(0, candidates.count - 1)) * 4)
    let widths = candidates.enumerated().map { index, text in
      ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width) + 28
    }
    // Keep ordinary words at natural width; cap long phrases so all five remain reachable.
    var remaining = available
    var sizes = Array(repeating: CGFloat(0), count: widths.count)
    for i in widths.indices.sorted(by: { widths[$0] < widths[$1] }) {
      sizes[i] = min(widths[i], remaining / CGFloat(widths.count - sizes.filter { $0 > 0 }.count))
      remaining -= sizes[i]
    }
    var x: CGFloat = 12
    return sizes.map { width in
      defer { x += width + 4 }
      return NSRect(x: x, y: 35, width: width, height: 36)
    }
  }
  func candidate(at point: NSPoint) -> Int? { candidateRects.firstIndex { $0.contains(point) } }
  override func draw(_ dirtyRect: NSRect) {
    RoarkTPanelDesign.surface(bounds)
if statusOnly {
  RoarkTPanelDesign.accentSoft.setFill()
  NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 40, height: 40), xRadius: 10, yRadius: 10).fill()
  RoarkTPanelDesign.text("中", in: NSRect(x: 15, y: 13, width: 20, height: 22), size: 17, color: RoarkTPanelDesign.accent, weight: .semibold)
  RoarkTPanelDesign.text(preedit, in: NSRect(x: 52, y: 16, width: bounds.width - 64, height: 18), color: RoarkTPanelDesign.foreground, weight: .medium)
  return
}
RoarkTPanelDesign.text(preedit, in: NSRect(x: 12, y: 12, width: bounds.width - 24, height: 16),
                           size: 12, color: RoarkTPanelDesign.secondary)
    for (i, rect) in candidateRects.enumerated() {
      if i == selected {
        RoarkTPanelDesign.accent.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill() // Radius.control
      }
      RoarkTPanelDesign.text("\(i + 1)", in: NSRect(x: rect.minX + 8, y: rect.minY + 11, width: 8, height: 14),
                             size: 11, color: i == selected ? RoarkTPanelDesign.onAccent : RoarkTPanelDesign.tertiary)
      RoarkTPanelDesign.text(candidates[i], in: NSRect(x: rect.minX + 20, y: rect.minY + 9, width: max(0, rect.width - 28), height: 18),
                             color: i == selected ? RoarkTPanelDesign.onAccent : RoarkTPanelDesign.foreground)
    }
  }
}

private final class CandidateAccessibilityElement: NSAccessibilityElement {
  var press: (() -> Void)?
  override func accessibilityPerformPress() -> Bool { press?(); return true }
}
