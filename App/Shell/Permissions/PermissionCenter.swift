import AppKit
import Observation
import RoarkTPlatform

/// Retain one instance in the app shell; start/stop follow the shell lifetime.
@MainActor @Observable final class PermissionCenter {
    struct Item: Identifiable {
        let kind: Permissions.Kind
        var status: Permissions.Status
        var id: Permissions.Kind { kind }
        var title: String {
            switch kind {
            case .accessibility: "辅助功能"
            case .screenRecording: "屏幕录制"
            case .microphone: "麦克风"
            }
        }
        var purpose: String {
            switch kind {
            case .accessibility: "用于读取选中文字与监听按住 Fn；不会在密码框中取词。"
            case .screenRecording: "仅在你主动截图时读取屏幕，用于截图和本地文字识别。"
            case .microphone: "仅在你按住说话时录音，用于本地语音识别。"
            }
        }
        var statusText: String {
            switch status {
            case .granted: "已授权"
            case .notGranted: "未授权"
            case .notDetermined: "尚未请求"
            case .denied: "已拒绝"
            case .restricted: "受系统策略限制"
            }
        }
    }

    private(set) var items: [Item] = []
    private(set) var requesting: Permissions.Kind?
    private(set) var message: String?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let read: @MainActor (Permissions.Kind) -> Permissions.Status
    @ObservationIgnored private let requestAccess: @MainActor (Permissions.Kind) async throws -> Void
    @ObservationIgnored private let open: @MainActor (Permissions.Kind) -> Bool

    init(read: @escaping @MainActor (Permissions.Kind) -> Permissions.Status = Permissions.status,
         request: @escaping @MainActor (Permissions.Kind) async throws -> Void = Permissions.request,
         open: @escaping @MainActor (Permissions.Kind) -> Bool = Permissions.openSettings) {
        self.read = read; self.requestAccess = request; self.open = open
        refresh()
    }

    func refresh() { items = Permissions.Kind.allCases.map { Item(kind: $0, status: read($0)) } }

    func start() {
        guard refreshTask == nil else { return }
        refresh()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                self?.refresh()
            }
        }
    }

    func stop() { refreshTask?.cancel(); refreshTask = nil }

    /// Called only by an explicit button for this single permission.
    func request(_ kind: Permissions.Kind) async {
        guard requesting == nil else { return }
        requesting = kind; message = nil
        defer { requesting = nil; refresh() }
        do { try await requestAccess(kind) }
        catch { message = "无法申请权限。请在“系统设置”的“隐私与安全性”中检查 RockType 的权限。" }
    }

    func openSettings(_ kind: Permissions.Kind) {
        message = open(kind) ? nil : "无法打开系统设置，请手动前往“隐私与安全性”。"
    }

    isolated deinit { refreshTask?.cancel() }
}
