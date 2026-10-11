import SwiftUI

struct ScreenshotLocalImageTools: View {
    @Bindable var session: ScreenshotSession
    @Environment(\.colorScheme) private var scheme
    private var p: Tokens.Palette { Tokens.palette(scheme) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("覆盖式图片翻译", systemImage: "character.bubble.fill").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(session.overlay.engine).font(.system(size: 11)).foregroundStyle(p.secondary)
            }
            HStack {
                Picker("翻译方式", selection: $session.overlayUsesAI) {
                    Text("优先离线翻译").tag(false)
                    Text("AI 翻译").tag(true)
                }.labelsHidden().frame(width: 150).disabled(session.busy)
                Button(session.overlay.phase == .failed ? "重试生成译图" : "生成译图") { session.translateImage() }
                    .disabled(session.busy)
                if session.overlay.phase == .running {
                    ProgressView().controlSize(.small)
                    Button("取消") { session.cancel() }
                }
                Spacer(minLength: 0)
            }.buttonStyle(DesignButtonStyle(variant: .secondary))
            Text(session.overlay.phase == .running ? (session.overlay.thinking ? "思考中…" : "正在翻译并生成译图…")
                 : session.overlay.notice ?? "按图片中识别到的文字区域翻译，不使用编辑后的文字。离线翻译不可用时，可按设置使用 AI；只发送文字，不发送图片。")
                .font(.system(size: 11)).foregroundStyle(session.overlay.phase == .failed ? p.warn : p.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if session.overlay.image != nil {
                HStack {
                    Text("译图已生成，可在上方切换原图与译图。").font(.system(size: 11)).foregroundStyle(p.secondary)
                    Spacer(minLength: 0)
                }
                HStack {
                    Button("复制译图") { session.showTranslatedImage = true; session.copyImage() }
                    Button("保存译图…") { session.showTranslatedImage = true; session.save() }
                    Button("将译图贴到屏幕") { session.showTranslatedImage = true; session.pinDisplayedImage() }
                }.buttonStyle(DesignButtonStyle(variant: .secondary))
            }
        }.padding(Tokens.Space.md).frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(p.line, lineWidth: 1))
    }
}

struct ScreenshotBarcodeResults: View {
    @Bindable var session: ScreenshotSession
    @Environment(\.colorScheme) private var scheme
    private var p: Tokens.Palette { Tokens.palette(scheme) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("二维码与条码", systemImage: "qrcode.viewfinder").font(.system(size: 13, weight: .semibold))
                Spacer()
                if session.barcodes.phase == .running {
                    ProgressView().controlSize(.small)
                    Button("取消识别") { session.barcodes.cancel() }
                } else {
                    Button(session.barcodes.phase == .idle ? "本机识别" : "重新识别") { session.recognizeCodes() }
                }
            }
            if session.barcodes.codes.isEmpty {
                Text(status).font(.system(size: 12)).foregroundStyle(p.secondary)
            }
            ForEach(Array(session.barcodes.codes.enumerated()), id: \.offset) { index, code in
                VStack(alignment: .leading, spacing: 6) {
                    Text(code.symbology.replacingOccurrences(of: "VNBarcodeSymbology", with: ""))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                    Text(verbatim: code.payload).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Button("复制内容") { session.copyText(code.payload) }
                        if code.webURL != nil { Button("查看完整链接…") { session.barcodes.previewURL(at: index) } }
                    }.buttonStyle(DesignButtonStyle(variant: .secondary))
                }.padding(10).background(p.canvas, in: RoundedRectangle(cornerRadius: 7))
            }
            if let url = session.barcodes.pendingURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text("确认后将在默认浏览器打开以下链接").font(.system(size: 13, weight: .semibold))
                    ScrollView {
                        Text(verbatim: url.absoluteString).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 160)
                    HStack {
                        Button("取消") { session.barcodes.dismissURL() }
                        Button("确认打开链接") {
                            if !session.barcodes.confirmURL() { session.notice = "无法打开链接，请复制后自行检查。" }
                        }
                    }.buttonStyle(DesignButtonStyle(variant: .secondary))
                }.padding(12).background(p.cardSecondary, in: RoundedRectangle(cornerRadius: 7))
            }
        }.padding(Tokens.Space.md).frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(p.line, lineWidth: 1))
    }
    private var status: String {
        switch session.barcodes.phase {
        case .idle: "识别文字时也会识别二维码与条码，也可单独识别；不会自动打开链接。"
        case .running: "正在本机识别…"
        case .done: "未识别到二维码或条码内容，可换用更清晰的图片后重试。"
        case .failed: "识别失败，请重试或使用更清晰的图片。"
        case .cancelled: "识别已取消。"
        }
    }
}
