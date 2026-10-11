// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

// Only the controller/configuration boundary is replaced. All drawing, layout,
// state presentation and accessibility actions are production panel code.
final class SquirrelConfig {}
@MainActor final class SquirrelInputController {
  var selected: Int?
  func selectCandidate(_ index: Int) -> Bool {
    selected = index
    return true
  }
  func highlightCandidate(_ index: Int) {}
  func page(up: Bool) -> Bool { true }
  func learningMenu(for index: Int) -> NSMenu? { nil }
  func performTranslationAction() {}
}
extension NSRange { static var empty: NSRange { NSRange(location: 0, length: 0) } }

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
    for screen in [
      NSRect(x: 0, y: 0, width: 1440, height: 900),
      NSRect(x: -1920, y: -200, width: 1920, height: 1080),
    ] {
      for point in [
        NSPoint(x: screen.minX, y: screen.minY), NSPoint(x: screen.maxX - 1, y: screen.maxY - 1),
      ] {
        let placed = RoarkTPanelDesign.place(
          size: NSSize(width: 420, height: 83),
          caret: NSRect(origin: point, size: NSSize(width: 1, height: 20)), screen: screen)
        precondition(screen.contains(placed), "edge and secondary screen bounds")
      }
    }
    let caret = NSRect(x: 100, y: 500, width: 1, height: 20)
    let controller = SquirrelInputController()
    let candidate = SquirrelPanel(position: caret)
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
      candidate.update(
        preedit: "zao shang hao", selRange: .empty, caretPos: 12,
        candidates: ["早上好", "早上", "早", "找", "照"], comments: [], labels: [], highlighted: 0, page: 0,
        lastPage: false, update: true)
      precondition(!candidate.canBecomeKey && !candidate.canBecomeMain)
      let buttons = candidate.contentView!.accessibilityChildren() as! [NSAccessibilityElement]
      precondition(buttons.count == 5)
      precondition(buttons[2].accessibilityPerformPress() && controller.selected == 2)
      try render(candidate, "candidate-" + name)
      var session = RoarkTCandidateTranslationSession()
      let ticket = session.observe(known)!
      session.receive("Hello", for: ticket)
      translation.show(session, beside: candidate)
      let row = translation.contentView!
      precondition(!translation.canBecomeKey && row.accessibilityPerformPress())
      precondition(activations > 0)
      try render(translation, "translation-ready-" + name)
      let next = session.observe(other)!
      translation.show(session, beside: candidate)
      precondition(row.accessibilityLabel() == "翻译中：正在翻译…", "old retained result never displayed")
      precondition(!row.accessibilityPerformPress(), "loading cannot commit old text")
      try render(translation, "translation-loading-" + name)
      session.fail(.requiresMacOS26, for: next)
      translation.show(session, beside: candidate)
      precondition(row.accessibilityLabel()?.hasPrefix("不可用：") == true)
      precondition(!row.accessibilityPerformPress())
      try render(translation, "translation-unavailable-" + name)
      session.invalidate()
      let fallback = session.observe(known)!
      session.fail(.serviceUnavailable, for: fallback)
      translation.show(session, beside: candidate)
      precondition(row.accessibilityLabel() == "候选翻译：hello")
      precondition(row.accessibilityPerformPress(), "exact static fallback remains committable")
      try render(translation, "translation-static-" + name)
      session.invalidate()
      let long = session.observe(known)!
      session.receive(
        String(repeating: "A long translation remains on a single line. ", count: 8), for: long)
      translation.show(session, beside: candidate)
      precondition(
        translation.frame.height == 60, "long translation never grows over application content")
      try render(translation, "translation-long-" + name)
      session.invalidate()
      translation.show(session, beside: candidate)
      precondition(!translation.isVisible)
      let mode = RoarkTInputModePanel()
      for ascii in [false, true] {
        mode.show(ascii: ascii, caret: caret)
        precondition(!mode.canBecomeKey && !mode.canBecomeMain)
        try render(mode, "mode-\(ascii ? "english" : "chinese")-" + name)
      }
      mode.hide()
      candidate.updateStatus(long: "小鹤双拼", short: "")
      candidate.update(
        preedit: "", selRange: .empty, caretPos: 0, candidates: [], comments: [], labels: [],
        highlighted: 0, page: 0, lastPage: true, update: true)
      try render(candidate, "mode-scheme-" + name)
      candidate.hide()
    }
    print(
      "Production panels passed: stale/loading/unavailable/long states, accessibility actions, edge geometry; PNGs: \(output.path)"
    )
  }
}
