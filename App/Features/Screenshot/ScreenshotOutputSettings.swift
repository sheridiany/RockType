import AppKit
import SwiftUI
import RoarkTCore

struct ScreenshotOutputSettings: View {
    @Binding var settings: ScreenshotSettings

    var body: some View {
        U4Card {
            Text("快速保存目录")
            Text(settings.saveDirectory ?? "~/Pictures/RockType")
                .font(Tokens.Typography.font(Tokens.Typography.caption))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("选择文件夹…", action: chooseDirectory)
                Button("恢复默认") { settings.saveDirectory = nil }
                    .disabled(settings.saveDirectory == nil)
            }
            Text("⇧↩ 保存 PNG 并复制文件路径；不受另存格式影响。")
                .font(Tokens.Typography.font(Tokens.Typography.caption))
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.directoryURL = try? ScreenshotOutput.directory(settings)
        panel.begin { response in
            if response == .OK, let url = panel.url { settings.saveDirectory = url.path }
        }
    }
}
