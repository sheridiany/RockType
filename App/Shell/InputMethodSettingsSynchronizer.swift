import Foundation
import RoarkTCore

@MainActor
final class InputMethodSettingsSynchronizer {
    private let writer: RimeSettingsPatchWriter
    private let post: (Notification.Name) -> Void
    init(writer: RimeSettingsPatchWriter = .init(), post: @escaping (Notification.Name) -> Void = { name in
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }) {
        self.writer = writer; self.post = post
    }

    /// Called only after settings.json is durable. A notification carries no preferences or content.
    func publish(_ settings: AppSettings) -> String? {
        var redeploy = false
        defer {
            post(InputMethodSettingsNotification.changed)
            if redeploy { post(InputMethodSettingsNotification.redeploy) }
        }
        do {
            let result = try writer.write(settings.input)
            if !result.conflicts.isEmpty {
                return "输入法偏好已保存；检测到自行维护的 " + result.conflicts.joined(separator: "、") + "，未覆盖。请手动合并 Rime 配置后重新部署。"
            }
            redeploy = result.changed
            return nil
        } catch {
            return "输入法偏好已保存，但 Rime 配置写入失败；请检查 Rime 目录权限后重试。"
        }
    }
}
