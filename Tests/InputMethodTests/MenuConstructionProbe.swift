// SPDX-License-Identifier: GPL-3.0-or-later
// Isolated executable: no IMK server, registration, Rime session, or real action execution.
import AppKit

@MainActor final class MenuActionProbe: NSObject, RoarkTInputMenuActions {
    var invocations = 0
    @objc func deploy() { invocations += 1 }
    @objc func syncUserData() { invocations += 1 }
    @objc func openLogFolder() { invocations += 1 }
    @objc func openRimeFolder() { invocations += 1 }
    @objc func openRoarkTSettings() { invocations += 1 }
}

@main enum MenuConstructionProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        let target = MenuActionProbe()
        for available in [false, true] {
            for _ in 0..<10 {
                let menu = makeRoarkTInputMenu(target: target, settingsAvailable: available)
                menu.update()
                precondition(!menu.items.isEmpty)
                if !available { precondition(menu.items.last?.action == nil && menu.items.last?.isEnabled == false) }
                for item in menu.items where !item.isSeparatorItem {
                    precondition(!item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    precondition(item.target === target)
                    guard let action = item.action else {
                        precondition(!item.isEnabled)
                        continue
                    }
                    precondition(target.responds(to: action))
                    if let image = item.image {
                        precondition(image.isValid && image.size.width > 0 && image.size.height > 0)
                    }
                    let isSettings = action == #selector(RoarkTInputMenuActions.openRoarkTSettings)
                    precondition(item.isEnabled == (!isSettings || available))
                    if item.isEnabled {
                        let previous = target.invocations
                        precondition(NSApp.sendAction(action, to: target, from: item))
                        precondition(target.invocations == previous + 1)
                    }
                }
            }
        }
        print("Production menu: 20 constructions and stub action dispatches passed")
    }
}
