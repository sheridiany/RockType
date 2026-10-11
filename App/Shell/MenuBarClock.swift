import AppKit
import Observation

/// Rebuild formatters on every refresh: the local zone may change while asleep.
@MainActor @Observable
final class MenuBarClock {
    private(set) var beijingTime = ""
    private(set) var beijingDate = ""
    private(set) var localTime = ""
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored var didRefresh: (() -> Void)?

    init() {
        refresh()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(wake),
                                               name: .NSSystemTimeZoneDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(wake),
                                               name: .NSSystemClockDidChange, object: nil)
    }

    func refresh(at date: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        formatter.dateFormat = "M月d日 EEEE"
        let day = formatter.string(from: date)
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm zzz"
        let local = formatter.string(from: date)
        guard time != beijingTime || day != beijingDate || local != localTime else { return }
        beijingTime = time
        beijingDate = day
        localTime = local
        didRefresh?()
    }

    @objc private func wake(_ notification: Notification) { refresh() }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
