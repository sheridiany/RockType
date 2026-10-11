import AppKit
import SwiftUI

enum AboutDocuments: String, CaseIterable {
    case appLicense = "RockType-MIT.txt"
    case inputLicense = "GPL-3.0.txt"
    case thirdParty = "THIRD_PARTY_NOTICES.md"
    var title: String {
        switch self {
        case .appLicense: "主程序许可证（MIT）"
        case .inputLicense: "输入法许可证（GPL v3）"
        case .thirdParty: "第三方声明"
        }
    }
    func url(resources: URL?) -> URL? {
        guard let resources else { return nil }
        let url = resources.appendingPathComponent("Licenses").appendingPathComponent(rawValue)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    static func version(_ info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版本"
        guard let build = info["CFBundleVersion"] as? String else { return version }
        return "\(version)（构建 \(build)）"
    }
}

struct AboutLegalLinks: View {
    @State private var message: String?
    var body: some View {
        DesignSectionTitle(title: "许可证与声明")
        DesignCard {
            ForEach(AboutDocuments.allCases, id: \.rawValue) { document in
                Button(document.title) {
                    guard let url = document.url(resources: Bundle.main.resourceURL) else {
                        message = "此构建未包含许可证文件，请使用完整安装包。"; return
                    }
                    message = NSWorkspace.shared.open(url) ? nil : "无法打开文档，请检查默认文本阅读应用。"
                }.buttonStyle(DesignButtonStyle(variant: .ghost))
            }
            if let message { Notice(text: message, tone: .warn) }
        }
    }
}
