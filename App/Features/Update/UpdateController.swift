import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()
    @Published private(set) var message = ""
    @Published private(set) var canCheck = false
    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    static func configurationReady(_ info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host == "github.com",
              url.path.hasSuffix("/appcast.xml"), !feed.contains("REPLACE_"),
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32 else { return false }
        return true
    }

    /// Call from applicationDidFinishLaunching. About also calls this idempotently.
    /// The release owner must supply the repository URL and public key before enabling checks.
    func start() {
        guard controller == nil else { return }
        guard Self.configurationReady(Bundle.main.infoDictionary ?? [:]) else {
            message = "此版本尚未配置更新来源，请从官方发布页下载新版本。"
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        do {
            try controller.updater.start()
            message = "更新包含主程序和输入法，安装时会请求管理员授权。"
            canCheck = controller.updater.canCheckForUpdates
            observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
                let available = change.newValue ?? false
                Task { @MainActor in self?.canCheck = available }
            }
        } catch {
            message = "更新服务未能启动，请重新打开 RoarkT 后重试。"
            self.controller = nil
        }
    }

    func check() {
        start()
        guard let controller, controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }
}
