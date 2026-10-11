import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject private var updates = UpdateController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("检查更新…") { updates.check() }.disabled(!updates.canCheck)
            Text(updates.message).font(.caption).foregroundStyle(.secondary)
        }.onAppear { updates.start() }
    }
}
