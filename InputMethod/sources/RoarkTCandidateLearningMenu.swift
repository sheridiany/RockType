import AppKit

/// A context-menu action, not another overlay or a parallel learning store.
enum RoarkTCandidateLearningMenu {
  static func make(candidate: String, canForget: Bool, perform: @escaping () -> Void) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let item = LearningMenuItem(title: "忘记「\(candidate)」的学习记录", perform: perform)
    item.isEnabled = canForget
    if !canForget { item.toolTip = "此候选没有可清除的个人学习记录" }
    menu.addItem(item)
    return menu
  }
}

private final class LearningMenuItem: NSMenuItem {
  private let perform: () -> Void

  init(title: String, perform: @escaping () -> Void) {
    self.perform = perform
    super.init(title: title, action: #selector(invoke), keyEquivalent: "")
    target = self
  }

  required init(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

  @objc private func invoke() {
    guard isEnabled else { return }
    perform()
  }
}
