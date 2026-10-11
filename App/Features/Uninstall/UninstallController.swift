import AppKit
import Carbon
import ServiceManagement
import RoarkTCore

@MainActor
enum UninstallController {
    static func confirm() {
        guard Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/RoarkT.app" else {
            show("请从 /Applications 中打开已安装的 RoarkT 后卸载。")
            return
        }
        let alert = NSAlert()
        alert.messageText = "卸载 RoarkT？"
        alert.informativeText = "将移除主程序、输入法和后台服务，并请求管理员授权。请先切换到其他输入法，退出其他已登录账户。默认保留设置、模型、钥匙串与学习数据。共享词典和无法确认归属的 custom.yaml 始终保留。"
        alert.addButton(withTitle: "卸载")
        alert.addButton(withTitle: "取消")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "同时删除我的数据（仅当前账户）"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let deleteData = alert.suppressionButton?.state == .on
        Task {
            do { try await perform(deleteData: deleteData) }
            catch { show("卸载未完成或已取消。请确认已切换输入法、其他账户已退出，然后重试。用户数据尚未安排清理。") }
        }
    }

    private static func show(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "RoarkT 卸载"
        alert.informativeText = message
        alert.runModal()
    }

    static func appleScriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func perform(deleteData: Bool) async throws {
        // Prepare a user-owned helper before the installed bundle is removed. It waits for
        // this process to exit, so SettingsStore's final flush cannot recreate deleted data.
        var cleanup: URL?
        if deleteData {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let destination = folder.appendingPathComponent("RoarkTCleanupUserData")
            do {
                try FileManager.default.copyItem(at: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/RoarkTCleanupUserData"), to: destination)
                cleanup = destination
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
        }
        defer {
            if let cleanup { try? FileManager.default.removeItem(at: cleanup.deletingLastPathComponent()) }
        }
        let filter = [kTISPropertyBundleID as String: Identifiers.inputMethodBundleID] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
        for source in sources {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
            guard [Identifiers.pinyinInputSourceID, Identifiers.flypyInputSourceID].contains(id) else { continue }
            guard let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(enabled).takeUnretainedValue()) else { continue }
            guard TISDisableInputSource(source) == noErr else { throw CocoaError(.userCancelled) }
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Identifiers.inputMethodBundleID)
            where app.bundleURL?.standardizedFileURL.path == "/Library/Input Methods/RoarkT Input.app" {
            _ = app.terminate()
            for _ in 0..<80 where !app.isTerminated { try await Task.sleep(for: .milliseconds(100)) }
            guard app.isTerminated else { throw CocoaError(.userCancelled) }
        }
        if SMAppService.mainApp.status == .enabled { try await SMAppService.mainApp.unregister() }
        // Only constant program paths are elevated. No user-writable script is executed as root.
        let uid = getuid()
        guard uid >= 500 else { throw CocoaError(.fileWriteNoPermission) }
        let command = """
        set -eu
        for other in $(/bin/ps -axo uid=,command= | /usr/bin/awk '$1 >= 500 && $2 == "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow" {print $1}'); do
          [ "$other" = "\(uid)" ] || exit 1
        done
        /bin/rm -f /Library/LaunchAgents/com.roarkist.roarkt.translation.plist
        if /bin/launchctl print gui/\(uid)/com.roarkist.roarkt.translation >/dev/null 2>&1; then
          /bin/launchctl bootout gui/\(uid)/com.roarkist.roarkt.translation
        fi
        /bin/rm -rf '/Library/Input Methods/RoarkT Input.app' /Applications/RoarkT.app
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: "do shell script " + appleScriptLiteral(command) + " with administrator privileges") else { throw CocoaError(.fileWriteUnknown) }
        script.executeAndReturnError(&error)
        guard error == nil else { throw CocoaError(.userCancelled) }
        // TIS has no public unregister API. Bundle removal plus logout clears registration.
        show("程序已移除。请注销并重新登录，以清除系统缓存的输入源。RoarkT 现在将退出。")
        if let executable = cleanup {
            let process = Process()
            process.executableURL = executable
            process.arguments = [String(ProcessInfo.processInfo.processIdentifier)]
            try process.run()
            cleanup = nil // The helper removes itself after cleanup.
        }
        NSApp.terminate(nil)
    }
}
