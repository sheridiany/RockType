import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject private var updates = UpdateController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsControlRow("软件更新", detail: updates.message, symbol: "arrow.triangle.2.circlepath") {
                Button("检查更新…") { updates.check() }.disabled(!updates.canCheck)
            }
        }.onAppear { updates.start() }
    }
}
