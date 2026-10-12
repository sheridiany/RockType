import SwiftUI

struct ScreenshotBatchPreview: View {
    @Bindable var batch: ScreenshotBatch
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ScreenshotLabel("批量识别", systemImage: ScreenshotSymbols.stack)
                Text("\(batch.index + 1) / \(batch.sessions.count)").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button { batch.select(batch.index - 1) } label: { ScreenshotLabel("上一张", systemImage: ScreenshotSymbols.previous) }.disabled(batch.index == 0)
                Button { batch.select(batch.index + 1) } label: { ScreenshotLabel("下一张", systemImage: ScreenshotSymbols.next) }.disabled(batch.index + 1 == batch.sessions.count)
            }.font(.system(size: 12)).padding(12)
            ScreenshotPreviewContent(session: batch.current).id(batch.index)
        }.modifier(DesignSurface())
    }
}
