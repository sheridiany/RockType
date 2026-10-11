import AppKit
import InputMethodKit

/// A transient caret badge, never a focusable window or a numbered candidate.
final class RoarkTInputModePanel: NSPanel {
  private let badge = ModeBadgeView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
  private var dismissal: Timer?
  private weak var inputClient: IMKTextInput?
  private var lastAscii: Bool?

  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
               styleMask: [.borderless, .nonactivatingPanel],
               backing: .buffered, defer: false)
    contentView = badge
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    isReleasedWhenClosed = false
  }

  /// ASCII mode belongs to this badge; other option notices keep their legacy UI.
  static func showsLegacyStatus(for optionName: String) -> Bool {
    optionName != "ascii_mode"
  }

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
    client.attributes(forCharacterIndex: index == NSNotFound ? 0 : index, lineHeightRectangle: &caret)
    show(ascii: ascii, caret: caret)
  }

  func show(ascii: Bool, caret: NSRect) {
    hide()
    guard caret.origin.x.isFinite, caret.origin.y.isFinite, caret.height > 0,
          let screen = NSScreen.screens.first(where: { $0.frame.intersects(caret) }) else { return }
    let bounds = screen.visibleFrame
    let side: CGFloat = 40
    let originX = min(max(caret.minX, bounds.minX), bounds.maxX - side)
    let below = caret.minY - side - 5
    let originY = min(max(below >= bounds.minY ? below : caret.maxY + 5, bounds.minY), bounds.maxY - side)
    badge.ascii = ascii
    setFrameOrigin(NSPoint(x: originX, y: originY))
    orderFrontRegardless()
    dismissal = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.hide() } }
  }

  func hide() {
    dismissal?.invalidate()
    dismissal = nil
    orderOut(nil)
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
    // Native fallback, not AI-generated artwork. Optional transparent PNGs can
    // replace it once the explicitly requested image service is available.
    let resource = ascii ? "roarktModeEn" : "roarktModeZh"
    if let url = Bundle.main.url(forResource: resource, withExtension: "png"),
       let image = NSImage(contentsOf: url) {
      image.draw(in: bounds)
      return
    }
    let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
    (ascii ? NSColor(srgbRed: 0.96, green: 0.32, blue: 0.10, alpha: 1)
           : NSColor(srgbRed: 0.98, green: 0.97, blue: 0.94, alpha: 1)).setFill()
    circle.fill()
    NSColor(srgbRed: 0.22, green: 0.21, blue: 0.20, alpha: 1).setStroke()
    circle.lineWidth = 1.3
    circle.stroke()
    let text = NSAttributedString(string: ascii ? "EN" : "中", attributes: [
      .font: NSFont.systemFont(ofSize: ascii ? 15 : 20, weight: .semibold),
      .foregroundColor: ascii ? NSColor.white : NSColor(srgbRed: 0.16, green: 0.16, blue: 0.15, alpha: 1)
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("中文输入")
  }

  required init?(coder: NSCoder) { nil }
}
