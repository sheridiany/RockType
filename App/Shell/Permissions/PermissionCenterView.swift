import SwiftUI

/// Live pane for S2 settings and S4 onboarding. The caller owns polling lifetime.
struct PermissionCenterView: View {
    @Bindable var center: PermissionCenter

    var body: some View {
        Form {
            ForEach(center.items) { item in
                Section(item.title) {
                    Text(item.purpose)
                    Text(item.statusText).foregroundStyle(.secondary)
                    HStack {
                        Button("请求\(item.title)权限") {
                            Task { await center.request(item.kind) }
                        }
                        .disabled(center.requesting != nil || item.status == .granted || item.status == .restricted)
                        Button("打开系统设置") { center.openSettings(item.kind) }
                    }
                }
            }
            if let message = center.message { Text(message).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
    }
}
