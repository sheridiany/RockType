import Foundation
import Observation
import RoarkTCore

/// The app's single preference owner. Bind directly to `settings`; subscribers see changes immediately.
@MainActor @Observable
final class SettingsStore {
    static let shared = SettingsStore()
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
    @ObservationIgnored private var readFailed = false
    @ObservationIgnored private let persistence: SettingsPersistence
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var firstPendingChange: ContinuousClock.Instant?

    init(persistence: SettingsPersistence = SettingsPersistence()) {
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
        guard !readFailed else { return } // Preserve an unreadable original until the next successful launch.
        do {
            try persistence.save(settings)
            persistenceError = nil
        } catch {
            persistenceError = "无法保存设置，请检查磁盘空间与文件访问权限。"
        }
    }
}
