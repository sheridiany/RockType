// SPDX-License-Identifier: GPL-3.0-or-later
// The production IMK menu, also built in the isolated menu round-trip checks.
import AppKit

@MainActor @objc protocol RoarkTInputMenuActions: AnyObject {
  func deploy()
  func syncUserData()
  func openLogFolder()
  func openRimeFolder()
  func openRoarkTSettings()
}

@MainActor
func makeRoarkTInputMenu(target: any RoarkTInputMenuActions, settingsAvailable: Bool) -> NSMenu {
  let deploy = NSMenuItem(title: NSLocalizedString("Deploy", comment: "Menu item"), action: #selector(RoarkTInputMenuActions.deploy), keyEquivalent: "`")
  deploy.target = target
  deploy.keyEquivalentModifierMask = [.control, .option]
  let sync = NSMenuItem(title: NSLocalizedString("Sync user data", comment: "Menu item"), action: #selector(RoarkTInputMenuActions.syncUserData), keyEquivalent: "")
  sync.target = target
  let logDir = NSMenuItem(title: NSLocalizedString("Logs...", comment: "Menu item"), action: #selector(RoarkTInputMenuActions.openLogFolder), keyEquivalent: "")
  logDir.target = target
  let setting = NSMenuItem(title: NSLocalizedString("Settings...", comment: "Menu item"), action: #selector(RoarkTInputMenuActions.openRimeFolder), keyEquivalent: "")
  setting.target = target
  let roarkTSettings = NSMenuItem(title: "RockType 设置…", action: settingsAvailable ? #selector(RoarkTInputMenuActions.openRoarkTSettings) : nil, keyEquivalent: "")
  roarkTSettings.target = target
  // IMK encoding enables every actionable item, even with autoenablesItems=false.
  // An unavailable Settings item must also have no action.
  roarkTSettings.isEnabled = settingsAvailable

  let menu = NSMenu()
  menu.autoenablesItems = false
  menu.addItem(deploy)
  menu.addItem(sync)
  menu.addItem(logDir)
  menu.addItem(setting)
  menu.addItem(.separator())
  menu.addItem(roarkTSettings)

  return menu
}
