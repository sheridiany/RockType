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
        candidate: theme.attrs, comment: theme.commentAttrs,
        cornerRadius: theme.cornerRadius,
        alpha: theme.alpha)
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
      let keycap = translation.contentView!.subviews.compactMap { $0 as? NSTextField }.first!
      precondition(!keycap.isHidden && keycap.accessibilityLabel() == "Tab 上屏译文")
      NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
        let ink = (keycap.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor).usingColorSpace(.deviceRGB)!
        let fill = NSColor(cgColor: keycap.layer!.backgroundColor!)!.usingColorSpace(.deviceRGB)!
        let surface = theme.backgroundColor.usingColorSpace(.deviceRGB)!
        func luminance(_ c: NSColor) -> CGFloat {
          let channels = [c.redComponent, c.greenComponent, c.blueComponent].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
          return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let a = fill.alphaComponent
        let composite = NSColor(srgbRed: fill.redComponent * a + surface.redComponent * (1-a), green: fill.greenComponent * a + surface.greenComponent * (1-a), blue: fill.blueComponent * a + surface.blueComponent * (1-a), alpha: 1)
        let l1 = luminance(ink), l2 = luminance(composite)
        precondition((max(l1, l2) + 0.05) / (min(l1, l2) + 0.05) >= 4.5, "Tab meets text contrast in both themes")
      }
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
      let ai = session.beginAI(known)
      translation.show(session, beside: candidate, style: style)
      precondition(row.attributedTitle.string == "AI 改写 · 思考中…" && !row.isEnabled)
      try render(translation, "ai-thinking-" + name)
      session.receive("synthetic AI result", for: ai)
      translation.show(session, beside: candidate, style: style)
      precondition(row.attributedTitle.string == "AI 改写 · synthetic AI result" && row.isEnabled)
      precondition(row.accessibilityLabel() == session.displayText && keycap.accessibilityLabel() == "Tab 上屏 AI 结果")
      precondition(row.accessibilityPerformPress())
      try render(translation, "ai-result-" + name)
      let missing = session.beginAI(known)
      session.fail("未配置 AI，请到设置启用并配置 AI", for: missing, retryable: false)
      translation.show(session, beside: candidate, style: style)
      precondition(row.attributedTitle.string.contains("未配置 AI") && !row.isEnabled)
      try render(translation, "ai-unconfigured-" + name)
      let failed = session.beginAI(known)
      session.fail("AI 网络失败，按 Tab 重试", for: failed)
      translation.show(session, beside: candidate, style: style)
      precondition(row.attributedTitle.string.contains("AI 翻译") && row.isEnabled)
      precondition(keycap.accessibilityLabel() == "Tab 重试 AI 请求")
      try render(translation, "ai-failed-" + name)
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
    // Exercise real drawing and hit testing across page boundaries, including
    // disabling paging while the same view previously had both arrows.
    let pagingConfig = SquirrelConfig()
    precondition(pagingConfig.load(yaml: "style:\n  show_paging: true\n"))
    let pagingPanel = SquirrelPanel(position: caret)
    pagingPanel.load(config: pagingConfig, forDarkMode: false)
    pagingPanel.load(config: pagingConfig, forDarkMode: true)
    func drawPage(_ page: Int, last: Bool) throws -> SquirrelView {
      pagingPanel.update(preedit: "", selRange: .empty, caretPos: 0,
        candidates: ["测试", "候选"], comments: [], labels: [], highlighted: 0,
        page: page, lastPage: last, update: true)
      try render(pagingPanel, "paging-check")
      return pagingPanel.contentView!.subviews.compactMap { $0 as? SquirrelView }.first!
    }
    func arrowPoint(in view: SquirrelView, up: Bool) -> NSPoint? {
      for y in stride(from: 0.0, through: view.bounds.height, by: 1) {
        for x in stride(from: 0.0, through: view.bounds.width, by: 1) {
          let point = NSPoint(x: x, y: y)
          if view.click(at: point).2 == up { return point }
        }
      }
      return nil
    }
    let pagingView = try drawPage(1, last: false)
    let upPoint = arrowPoint(in: pagingView, up: true)!
    let downPoint = arrowPoint(in: pagingView, up: false)!
    _ = try drawPage(0, last: false)
    precondition(pagingView.click(at: upPoint).2 == nil, "first page removes the old up hit area")
    _ = try drawPage(1, last: true)
    precondition(pagingView.click(at: downPoint).2 == nil, "last page removes the old down hit area")
    _ = try drawPage(1, last: false)
    precondition(pagingConfig.load(yaml: "style:\n  show_paging: false\n"))
    pagingPanel.load(config: pagingConfig, forDarkMode: false)
    pagingPanel.load(config: pagingConfig, forDarkMode: true)
    _ = try drawPage(1, last: false)
    precondition(pagingView.click(at: upPoint).2 == nil && pagingView.click(at: downPoint).2 == nil,
                 "disabled paging removes both old hit areas")
    pagingPanel.hide()
    // Freeze rendering/layout before moving geometry helpers. Exercise multiline,
    // surrogate-pair text, both list directions and both writing orientations.
    for layout in ["linear", "stacked"] {
      for orientation in ["horizontal", "vertical"] {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
          NSApp.appearance = NSAppearance(named: appearance)
          let config = SquirrelConfig()
          precondition(config.load(yaml: "style:\n  candidate_list_layout: \(layout)\n  text_orientation: \(orientation)\n  inline_preedit: false\n  show_paging: true\n"))
          let panel = SquirrelPanel(position: caret)
          panel.load(config: config, forDarkMode: false)
          panel.load(config: config, forDarkMode: true)
          panel.inputController = controller
          panel.update(preedit: "已选 ni hao", selRange: NSRange(location: 3, length: 6), caretPos: 9,
            candidates: ["你好", String(repeating: "跨行候选", count: 5), "SwiftUI", "𠀀汉字", "第五项"],
            comments: ["", "多行", "", "", ""], labels: ["1", "2", "3", "4", "5"],
            highlighted: 1, page: 1, lastPage: false, update: true)
          try render(panel, "geometry-\(layout)-\(orientation)-\(name)")
          let view = panel.contentView!.subviews.compactMap { $0 as? SquirrelView }.first!
          precondition(view.candidateRanges.count == 5)
          precondition(view.contentRect.width.isFinite && view.contentRect.height.isFinite)
          let items = view.accessibilityChildren() as! [NSAccessibilityElement]
          precondition(items.count == 5 && items[3].accessibilityPerformPress())
          precondition(controller.selected == 3, "surrogate-pair candidate keeps the selected index")
          precondition(view.click(at: NSPoint(x: -100, y: -100)).0 == nil)
          panel.hide()
        }
      }
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
