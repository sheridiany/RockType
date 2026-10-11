import SwiftUI

struct ScreenshotBatchPreview: View {
    @Bindable var batch: ScreenshotBatch
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("批量识别", systemImage: "photo.stack")
                Text("\(batch.index + 1) / \(batch.sessions.count)").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("上一张") { batch.select(batch.index - 1) }.disabled(batch.index == 0)
                Button("下一张") { batch.select(batch.index + 1) }.disabled(batch.index + 1 == batch.sessions.count)
            }.font(.system(size: 12)).padding(12)
            ScreenshotPreviewContent(session: batch.current).id(batch.index)
        }.modifier(DesignSurface())
    }
}
