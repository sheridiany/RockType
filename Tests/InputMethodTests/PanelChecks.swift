// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

// Only the controller boundary is replaced. All drawing, layout,
// state presentation and accessibility actions are production panel code. Theme YAML is parsed by production librime configuration.
@MainActor final class SquirrelInputController {
  var selected: Int?
  func selectCandidate(_ index: Int) -> Bool {
    selected = index
    return true
  }
  func highlightCandidate(_ index: Int) {}
  func page(up: Bool) -> Bool { true }
  func moveCaret(forward: Bool) -> Bool { true }
  func learningMenu(for index: Int) -> NSMenu? { nil }
  func performTranslationAction() {}
}


@main
struct PanelChecks {
  @MainActor static func main() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    func render(_ panel: NSPanel, _ name: String) throws {
      let view = panel.contentView!
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        fatalError("bitmap allocation")
      }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding")
      }
      try data.write(to: output.appendingPathComponent(name + ".png"))
    }
    let caret = NSRect(x: 100, y: 500, width: 1, height: 20)
    let controller = SquirrelInputController()
    let candidate = SquirrelPanel(position: caret)
    let config = SquirrelConfig()
    let yaml = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
    precondition(config.load(yaml: yaml))
    candidate.load(config: config, forDarkMode: false)
    candidate.load(config: config, forDarkMode: true)
    candidate.inputController = controller
    let translation = RoarkTTranslationPanel()
    var activations = 0
    translation.onActivate = { activations += 1 }
    let known = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
    let other = RoarkTCandidateSnapshot(
      rawInput: "nihao", source: "你号", identity: "0:5:1", scope: "whole")
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      app.appearance = NSAppearance(named: appearance)
      let theme = SquirrelTheme()
      theme.load(config: config, dark: name == "dark")
      let style = RoarkTTranslationPanel.Style(background: theme.backgroundColor, border: theme.borderColor,
        highlight: theme.highlightedBackColor, candidate: theme.attrs, comment: theme.commentAttrs,
        label: theme.labelAttrs, cornerRadius: theme.cornerRadius,
        shortcutCornerRadius: theme.hilitedCornerRadius, alpha: theme.alpha)
      candidate.update(
        preedit: "zao shang hao", selRange: .empty, caretPos: 12,
        candidates: ["早上好", "早上", "早", "找", "照"], comments: [], labels: [], highlighted: 0, page: 0,
        lastPage: false, update: true)
      precondition(!candidate.canBecomeKey && !candidate.canBecomeMain)
      let view = candidate.contentView!.subviews.compactMap { $0 as? SquirrelView }.first!
      let buttons = view.accessibilityChildren() as! [NSAccessibilityElement]
      precondition(buttons.count == 5)
      precondition(buttons[2].accessibilityPerformPress() && controller.selected == 2)
      try render(candidate, "candidate-" + name)
      var session = RoarkTCandidateTranslationSession()
      let ticket = session.observe(known)!
      session.receive("Hello", for: ticket)
      translation.show(session, beside: candidate, style: style)
      let row = translation.contentView!.subviews.compactMap { $0 as? NSButton }.first!
      precondition(!translation.canBecomeKey && row.accessibilityPerformPress())
      precondition(activations > 0)
      try render(translation, "translation-ready-" + name)
      candidate.updateTranslation(session)
      let attached = NSApp.windows.compactMap { $0 as? RoarkTTranslationPanel }
        .first { $0 !== translation && $0.isVisible }!
      candidate.update(preedit: "new", selRange: .empty, caretPos: 3,
        candidates: ["新"], comments: [], labels: [], highlighted: 0, page: 0, lastPage: true, update: true)
      let attachedRow = attached.contentView!.subviews.compactMap { $0 as? NSButton }.first!
      precondition(attached.isVisible && !attachedRow.isEnabled, "input changes invalidate in place without flicker")
      precondition(attachedRow.attributedTitle.string == "正在翻译…", "old translation is never shown after input changes")
      let next = session.observe(other)!
      translation.show(session, beside: candidate, style: style)
      precondition(row.accessibilityLabel() == "整句翻译：正在翻译…", "old retained result never displayed")
      precondition(!row.isEnabled, "loading cannot commit old text")
      try render(translation, "translation-loading-" + name)
      session.fail(.requiresMacOS26, for: next)
      translation.show(session, beside: candidate, style: style)
      precondition(row.accessibilityLabel()?.contains(session.displayText) == true)
      precondition(!row.isEnabled)
      try render(translation, "translation-unavailable-" + name)
      session.invalidate()
      let fallback = session.observe(known)!
      session.fail(.serviceUnavailable, for: fallback)
      translation.show(session, beside: candidate, style: style)
      precondition(row.accessibilityLabel() == "整句翻译：hello")
      precondition(row.accessibilityPerformPress(), "exact static fallback remains committable")
      try render(translation, "translation-static-" + name)
      session.invalidate()
      let long = session.observe(known)!
      session.receive(
        String(repeating: "A long translation wraps in the restored row. ", count: 8), for: long)
      translation.show(session, beside: candidate, style: style)
      precondition(
        translation.frame.height > 34 && translation.frame.height <= 130, "long translation wraps within the original measurement cap")
      try render(translation, "translation-long-" + name)
      session.invalidate()
      translation.show(session, beside: candidate, style: style)
      precondition(!translation.isVisible)
      let mode = RoarkTInputModePanel()
      for ascii in [false, true] {
        mode.show(ascii: ascii, caret: caret)
        precondition(!mode.canBecomeKey && !mode.canBecomeMain && mode.ignoresMouseEvents)
        precondition(mode.frame.size == NSSize(width: 40, height: 40))
        try render(mode, "mode-\(ascii ? "english" : "chinese")-" + name)
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.65))
      mode.show(ascii: false, caret: caret)
      RunLoop.current.run(until: Date().addingTimeInterval(0.55))
      precondition(mode.isVisible, "the cancelled old timer cannot dismiss the new badge")
      RunLoop.current.run(until: Date().addingTimeInterval(0.65))
      precondition(!mode.isVisible, "badge dismisses after approximately 1.1 seconds")
      mode.show(ascii: false, caret: caret)
      mode.hide()
      precondition(!mode.isVisible, "typing/focus hide is immediate")
      mode.show(ascii: true, caret: .zero)
      precondition(!mode.isVisible, "invalid caret cannot show a badge")
      candidate.updateStatus(long: "小鹤双拼", short: "")
      candidate.update(
        preedit: "", selRange: .empty, caretPos: 0, candidates: [], comments: [], labels: [],
        highlighted: 0, page: 0, lastPage: true, update: true)
      try render(candidate, "mode-scheme-" + name)
      for screen in NSScreen.screens {
        for point in [NSPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY),
                      NSPoint(x: screen.visibleFrame.maxX - 1, y: screen.visibleFrame.maxY - 20)] {
          candidate.position = NSRect(origin: point, size: NSSize(width: 1, height: 20))
          candidate.update(preedit: "", selRange: .empty, caretPos: 0, candidates: ["测试"],
            comments: [], labels: [], highlighted: 0, page: 0, lastPage: true, update: true)
          precondition(screen.frame.contains(candidate.frame), "candidate screen edge")
          var edge = RoarkTCandidateTranslationSession()
          let ticket = edge.observe(known)!
          edge.receive("Hello", for: ticket)
          translation.show(edge, beside: candidate, style: style)
          precondition(screen.visibleFrame.contains(translation.frame), "translation screen edge")
          mode.show(ascii: true, caret: candidate.position)
          precondition(screen.visibleFrame.contains(mode.frame), "badge screen edge")
        }
      }
      mode.hide()
      translation.orderOut(nil)
      candidate.position = caret
      candidate.hide()
    }
    var forgotten = false
    let learning = RoarkTCandidateLearningMenu.make(candidate: "测试", canForget: true) { forgotten = true }
    let item = learning.items[0]
    precondition(item.title == "忘记「测试」的学习记录")
    NSApp.sendAction(item.action!, to: item.target, from: item)
    precondition(forgotten)
    let disabled = RoarkTCandidateLearningMenu.make(candidate: "测试", canForget: false) {}
    precondition(!disabled.items[0].isEnabled && disabled.items[0].toolTip != nil)
    print(
      "Production panels passed: stale/loading/unavailable/long states, accessibility actions, edge geometry; PNGs: \(output.path)"
    )
  }
}
