import AppKit

// A compact action row, not a virtual Rime candidate or an activating window.
final class RoarkTTranslationPanel: NSPanel {
  struct Style {
    let background: NSColor
    let border: NSColor?
    let highlight: NSColor?
    let candidate: [NSAttributedString.Key: Any]
    let comment: [NSAttributedString.Key: Any]
    let label: [NSAttributedString.Key: Any]
    let cornerRadius: CGFloat
    let shortcutCornerRadius: CGFloat
    let alpha: CGFloat

    func actionAttributes(ready: Bool, appearance: NSAppearance) -> [NSAttributedString.Key: Any] {
      var attributes = candidate
      if !ready {
        let ink = comment[.foregroundColor] as? NSColor ?? .secondaryLabelColor
        // Desaturate custom comment colors too, so retained text reads as disabled.
        appearance.performAsCurrentDrawingAppearance {
          attributes[.foregroundColor] = ink.usingColorSpace(.deviceGray)?.withAlphaComponent(1) ?? ink
        }
      }
      return attributes
    }
  }

  private let shortcutLabel = NSTextField(labelWithString: "")
  private let action = TranslationActionButton(title: "", target: nil, action: nil)
  private let surface = NSView()
  var onActivate: (() -> Void)?

  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 34),
               styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    hidesOnDeactivate = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    surface.wantsLayer = true
    surface.layer?.masksToBounds = true
    surface.layer?.borderWidth = 0.5
    contentView = surface
    for label in [shortcutLabel] {
      label.alignment = .center
      label.wantsLayer = true
      surface.addSubview(label)
    }
    action.isBordered = false
    action.alignment = .left
    action.cell?.wraps = true
    action.cell?.lineBreakMode = .byWordWrapping
    action.target = self
    action.action = #selector(activate)
    surface.addSubview(action)
    setAccessibilityLabel("候选翻译区")
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  func show(_ state: RoarkTCandidateTranslationSession, beside parent: NSPanel, style: Style) {
    guard let ticket = state.ticket, parent.isVisible else { orderOut(nil); return }
    appearance = parent.appearance
    level = parent.level
    alphaValue = style.alpha
    surface.layer?.cornerRadius = style.cornerRadius
    shortcutLabel.layer?.cornerRadius = style.shortcutCornerRadius
    // Resolve dynamic AppKit colors under the same appearance as the candidate window.
    effectiveAppearance.performAsCurrentDrawingAppearance {
      surface.layer?.backgroundColor = style.background.cgColor
      surface.layer?.borderColor = (style.border ?? .clear).cgColor
      // A keycap is a control hint, not a selected candidate. Pair semantic ink
      // and fill rather than inheriting a low-contrast candidate number color.
      shortcutLabel.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
      shortcutLabel.layer?.borderColor = NSColor.separatorColor.cgColor
    }
    let scope = ticket.snapshot.scope == "whole" ? "整句" : "当前词"
    shortcutLabel.stringValue = "Tab"
    shortcutLabel.isHidden = state.commit == nil && !state.canRetry
    shortcutLabel.attributedStringValue = NSAttributedString(string: "Tab", attributes: [
      .font: NSFont.systemFont(ofSize: 11, weight: .medium),
      .foregroundColor: NSColor.labelColor
    ])
    shortcutLabel.layer?.borderWidth = 0.5
    shortcutLabel.layer?.cornerRadius = 4
    shortcutLabel.setAccessibilityLabel(state.canRetry ? "Tab 重试翻译" : "Tab 上屏译文")
    // A pending ticket may retain text from a previous candidate. Never draw it.
    let text = state.isLoading ? "正在翻译…" : state.displayText
    let attributes = style.actionAttributes(ready: state.commit != nil, appearance: effectiveAppearance)
    let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: NSFont.systemFontSize)
    action.attributedTitle = NSAttributedString(string: text, attributes: attributes)
    action.isEnabled = state.commit != nil || state.canRetry
    action.toolTip = state.commit?.text ?? state.failure
    action.setAccessibilityLabel("\(scope)翻译：\(text)")
    action.setAccessibilityHelp(state.canRetry ? "点击或按 Tab 重试，不会提交旧译文" : "翻译完成后点击译文或按 Tab 上屏")
    let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
    let width = min(max(parent.frame.width, 300), screen.width)
    let shortcutSize = shortcutLabel.attributedStringValue.size()
    let shortcutWidth = max(26, ceil(shortcutSize.width) + 8)
    let textWidth = width - shortcutWidth - 28
    let measured = (text as NSString).boundingRect(
      with: NSSize(width: textWidth, height: 100), options: [.usesLineFragmentOrigin],
      attributes: [.font: font])
    let height = max(34, ceil(max(measured.height, shortcutSize.height)) + 12)
    var origin = NSPoint(x: parent.frame.minX, y: parent.frame.minY - height - 3)
    if origin.y < screen.minY { origin.y = parent.frame.maxY + 3 }
    origin.x = max(screen.minX, min(origin.x, screen.maxX - width))
    origin.y = max(screen.minY, min(origin.y, screen.maxY - height))
    setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    action.frame = NSRect(x: 12, y: 3, width: textWidth, height: height - 6)
    shortcutLabel.frame = NSRect(x: width - shortcutWidth - 8, y: (height - shortcutSize.height - 4) / 2,
                                width: shortcutWidth, height: shortcutSize.height + 4)
    // Ordering an already visible panel forces a synchronous WindowServer round trip per key.
    if !isVisible { orderFront(nil) }
  }

  /// Input changed: keep the window in place (hiding and re-showing it on every key flickers and
  /// stalls the candidate window), but never show or commit the old translation.
  func markStale() {
    guard isVisible else { return }
    let attributes = action.attributedTitle.length > 0
      ? action.attributedTitle.attributes(at: 0, effectiveRange: nil) : [:]
    action.attributedTitle = NSAttributedString(string: "正在翻译…", attributes: attributes)
    action.isEnabled = false
    action.toolTip = nil
    shortcutLabel.isHidden = true
    let scope = action.accessibilityLabel()?.components(separatedBy: "：").first ?? "翻译"
    action.setAccessibilityLabel("\(scope)：正在翻译…")
  }

  @objc private func activate() { onActivate?() }
}

private final class TranslationActionButton: NSButton {
  override func accessibilityPerformPress() -> Bool {
    guard isEnabled else { return false }
    performClick(nil)
    return true
  }
}
