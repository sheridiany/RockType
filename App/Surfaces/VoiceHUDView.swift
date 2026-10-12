#if DEBUG
import SwiftUI

/// Live Gallery uses the production native surface. ImageRenderer cannot rasterize an
/// NSViewRepresentable, so reduced-motion/export previews use a snapshot of that SAME surface.
struct VoiceHUDView: View {
    let model: VoicePresentation
    var onCancel: () -> Void = {}
    @Environment(\.designReduceMotion) private var reduced
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @State private var hovering = false
    var body: some View {
        if reduced || systemReduced {
            Image(nsImage: snapshot())
                .accessibilityLabel(model.state.title)
                .overlay(alignment: .topTrailing) {
                    Button(action: onCancel) { Color.clear.frame(width: 18, height: 18) }
                        .buttonStyle(.plain).accessibilityLabel("关闭语音示例")
                        .padding(.top, 6).padding(.trailing, 5)
                }
                .onHover { hovering = $0 }
        } else {
            VoiceHUDNativePreview(model: model, onCancel: onCancel)
        }
    }
    private func snapshot() -> NSImage {
        let hud = RoarkTVoiceHUD(present: { _ in }, reduceMotion: { true })
        hud.render(model.state.presentation)
        for level in model.levels { hud.content.waveform.append(decibels: Float(level * 45 - 55)) }
        hud.content.layoutSubtreeIfNeeded()
        if hovering { hud.content.close.alphaValue = 1 }
        let bounds = hud.content.bounds
        guard let bitmap = hud.content.bitmapImageRepForCachingDisplay(in: bounds) else {
            preconditionFailure("Cannot render voice Gallery surface")
        }
        hud.content.cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size); image.addRepresentation(bitmap)
        return image
    }
}
private struct VoiceHUDNativePreview: NSViewRepresentable {
    let model: VoicePresentation
    let onCancel: () -> Void
    func makeNSView(context: Context) -> RoarkTVoiceHUDContent { RoarkTVoiceHUDContent() }
    func updateNSView(_ view: RoarkTVoiceHUDContent, context: Context) {
        view.render(model.state.presentation); view.onCancel = onCancel
        for level in model.levels { view.waveform.append(decibels: Float(level * 45 - 55)) }
        view.setRunning(true)
    }
    static func dismantleNSView(_ view: RoarkTVoiceHUDContent, coordinator: ()) { view.setRunning(false) }
}
struct VoiceHUDDemo: View {
    let initial: VoicePresentation.State
    @State private var dismissed = false
    var body: some View {
        if dismissed {
            Button("重新显示示例") { dismissed = false }.buttonStyle(DesignButtonStyle())
        } else {
            VoiceHUDView(model: .fixture(initial), onCancel: { dismissed = true })
                .frame(width: initial.presentation.size.width, height: initial.presentation.size.height)
        }
    }
}
#endif
