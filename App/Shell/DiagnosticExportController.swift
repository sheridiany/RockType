import AppKit
import UniformTypeIdentifiers
import RoarkTCore

@MainActor
final class DiagnosticExportController {
    private var exporting = false

    func export() {
        guard !exporting else { return }
        let panel = NSSavePanel()
        panel.title = "导出 RoarkT 诊断"
        panel.nameFieldStringValue = "RoarkT-Diagnostics-\(Int(Date().timeIntervalSince1970)).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.message = "仅导出动作类型、状态、耗时与脱敏错误，不含正文、截图或密钥。请选择新文件名。"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exporting = true
        Task {
            defer { exporting = false }
            do {
                try await DiagnosticLog.shared.record(.init(action: .diagnosticExport, status: .started))
                try await DiagnosticLog.shared.exportZIP(to: destination)
                try? await DiagnosticLog.shared.record(.init(action: .diagnosticExport, status: .succeeded))
                showMessage("诊断已导出", detail: "ZIP 文件已保存到你选择的位置。")
            } catch {
                try? await DiagnosticLog.shared.record(.init(action: .diagnosticExport, status: .failed, failure: .storage))
                showMessage("诊断导出失败", detail: "请使用尚不存在的文件名，并检查目标文件夹权限与磁盘空间后重试。")
            }
        }
    }

    private func showMessage(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
