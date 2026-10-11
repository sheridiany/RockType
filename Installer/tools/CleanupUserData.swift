import Foundation
import Darwin

@main
struct CleanupUserData {
    static func main() {
        guard getuid() != 0, CommandLine.arguments.count == 2,
              let parent = Int32(CommandLine.arguments[1]), parent > 1 else { exit(1) }
        let deadline = Date().addingTimeInterval(30)
        while kill(parent, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard kill(parent, 0) != 0 && errno == ESRCH else { exit(1) }
        do { try UninstallData.remove(in: FileManager.default.homeDirectoryForCurrentUser) }
        catch {
            // No content or user paths in logs. Surface failures after the main app has quit.
            let script = NSAppleScript(source: "display alert \"RoarkT 数据清理未完成\" message \"程序已卸载；请手动检查 RoarkT 设置目录。其他输入法文件已保留。\"")
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            exit(1)
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        // Only clean up our copied executable, never delete a directory supplied as an argument.
        try? FileManager.default.removeItem(at: executable)
        try? FileManager.default.removeItem(at: executable.deletingLastPathComponent())
    }
}
