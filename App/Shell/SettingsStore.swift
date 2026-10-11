import Foundation
import Observation
import RoarkTCore

/// The app's single preference owner. Bind directly to `settings`; subscribers see changes immediately.
@MainActor @Observable
final class SettingsStore {
    static let shared = SettingsStore(inputMethodSync: InputMethodSettingsSynchronizer())
    static let didChange = Notification.Name("RoarkTSettingsDidChange")

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            NotificationCenter.default.post(name: Self.didChange, object: self)
            scheduleSave()
        }
    }
    private(set) var loadStatus: SettingsPersistence.LoadStatus?
    /// Only a fixed message; underlying errors can contain paths or configuration contents.
    private(set) var persistenceError: String?
    private(set) var inputMethodSyncMessage: String?
    @ObservationIgnored private let inputMethodSync: InputMethodSettingsSynchronizer?
    @ObservationIgnored private var readFailed = false
    @ObservationIgnored private let persistence: SettingsPersistence
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var firstPendingChange: ContinuousClock.Instant?

    init(persistence: SettingsPersistence = SettingsPersistence(), inputMethodSync: InputMethodSettingsSynchronizer? = nil) {
        self.inputMethodSync = inputMethodSync
        self.persistence = persistence
        do {
            let loaded = try persistence.load()
            settings = loaded.settings
            loadStatus = loaded.status
        } catch {
            settings = .defaults
            readFailed = true
            persistenceError = "无法读取设置，请检查文件访问权限。"
        }
    }

    private func scheduleSave() {
        // Throttle, rather than debounce: continuous editing still reaches disk every 250 ms.
        guard firstPendingChange == nil else { return }
        firstPendingChange = .now
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            self?.flush()
        }
    }

    /// Call on application termination and before reading preferences from another process.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        firstPendingChange = nil
        if readFailed {
            // Retry the read: once the file is absent, or backed up as corrupt, writing cannot
            // destroy the user's only copy. A now-readable original is still never overwritten.
            guard let status = try? persistence.load().status, status != .loaded else { return }
            readFailed = false
        }
        do {
            try persistence.save(settings)
            persistenceError = nil
            inputMethodSyncMessage = inputMethodSync?.publish(settings)
        } catch {
            persistenceError = "无法保存设置，请检查磁盘空间与文件访问权限。"
        }
    }
}
