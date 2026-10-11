// GPL-3.0-or-later. Read-only preferences and content-free invalidation signals.
import AppKit

@MainActor
final class RoarkTInputSettings: NSObject {
  static let shared = RoarkTInputSettings()
  private(set) var preferences = InputMethodPreferences.load()
  private let controllers = NSHashTable<SquirrelInputController>.weakObjects()
  private var reloadTask: Task<Void, Never>?
  private var idleTask: Task<Void, Never>?
  private var redeployRequested = false
  private var redeploy: (() -> Void)?

  func start(redeploy: @escaping () -> Void) {
    guard self.redeploy == nil else { return }
    self.redeploy = redeploy
    let center = DistributedNotificationCenter.default()
    center.addObserver(self, selector: #selector(changed), name: InputMethodSettingsNotification.changed,
                       object: nil, suspensionBehavior: .deliverImmediately)
    center.addObserver(self, selector: #selector(deploymentRequested), name: InputMethodSettingsNotification.redeploy,
                       object: nil, suspensionBehavior: .deliverImmediately)
    // Close the gap between initial construction and observer installation.
    reload()
  }

  func track(_ controller: SquirrelInputController) { controllers.add(controller) }

  func stop() {
    DistributedNotificationCenter.default().removeObserver(self)
    reloadTask?.cancel(); reloadTask = nil
    idleTask?.cancel(); idleTask = nil
    redeploy = nil
  }

  @objc private func changed(_ notification: Notification) { reload() }
  @objc private func deploymentRequested(_ notification: Notification) {
    redeployRequested = true
    reload()
  }

  private func reload() {
    reloadTask?.cancel()
    // Coalesce changes; JSON IO/decoding never runs in an IMK key callback.
    reloadTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      let updated = await Task.detached(priority: .utility) { InputMethodPreferences.load() }.value
      guard !Task.isCancelled, let self else { return }
      if self.preferences != updated {
        self.preferences = updated
        for controller in self.controllers.allObjects { controller.applyPreferences(updated) }
      }
      self.applyWhenIdle()
    }
  }

  private func applyWhenIdle() {
    guard idleTask == nil else { return }
    idleTask = Task { @MainActor [weak self] in
      defer { self?.idleTask = nil }
      while !Task.isCancelled {
        guard let self else { return }
        let active = self.controllers.allObjects
        if !active.contains(where: \.hasActiveComposition) {
          for controller in active { controller.applyPendingScheme() }
          if self.redeployRequested {
            self.redeployRequested = false
            // Dispose cached sessions before the existing deploy path finalizes librime.
            for controller in active { controller.prepareForSettingsDeployment() }
            self.redeploy?()
          }
          return
        }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      }
    }
  }
}
