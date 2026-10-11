import SwiftUI
import RoarkTCore

struct ScreenshotVisualAIConfirmation: View {
    @Bindable var session: ScreenshotSession
    @State private var skipFuture = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        if let request = session.visual.request {
            VStack(alignment: .leading, spacing: 12) {
                Label("确认发送 · " + session.visual.title, systemImage: "paperplane")
                    .font(.system(size: 15, weight: .semibold))
                Text("将发送上方图片和下方文字至 \(request.connection.name.isEmpty ? "当前 AI 连接" : request.connection.name)（\(URL(string: request.connection.baseURL)?.host ?? "已配置端点")），模型：\(request.model)。")
                    .font(.system(size: 12)).foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true)
                if request.fallbackImageCapabilityVerified, let fallback = request.connection.fallbackModel {
                    Text("当前模型暂不可用且尚未输出正文时，可改用同一服务商已验证的备用模型：\(fallback)。")
                        .font(.system(size: 12)).foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    Text(request.text.isEmpty ? "（无识别文字，仅发送图片）" : request.text)
                        .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.frame(height: 160).background(p.canvas, in: RoundedRectangle(cornerRadius: 7))
                Toggle("以后不再询问", isOn: $skipFuture).toggleStyle(.checkbox)
                Text("仅省略你主动点击图片 AI 动作后的确认；可在“图片操作”中恢复每次询问。")
                    .font(.system(size: 11)).foregroundStyle(p.secondary)
                HStack {
                    Button("返回修改") { session.cancel() }.buttonStyle(DesignButtonStyle(variant: .secondary))
                    Spacer()
                    Button("确认发送图片与文字") { session.confirmImage(skipFuture: skipFuture) }
                        .buttonStyle(DesignButtonStyle(variant: .primary))
                }
            }.padding(16).background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
    }
}

struct ScreenshotVisualAIResult: View {
    @Bindable var session: ScreenshotSession
    @Environment(\.colorScheme) private var scheme
    private var title: String {
        switch session.visual.phase {
        case .thinking: "思考中…"
        case .running: "正在连接视觉模型…"
        case .streaming: "正在生成…"
        case .failed: "图片处理未完成"
        case .cancelled: "操作已取消"
        case .confirming: "请先确认发送内容"
        default: "图片与文字一起理解"
        }
    }
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(session.visual.phase == .idle ? "图片 AI" : session.visual.title, systemImage: "photo.badge.sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if session.visual.isBusy { ProgressView().controlSize(.small) }
                Text(session.visual.model).font(.system(size: 11)).foregroundStyle(p.secondary).lineLimit(1)
            }
            ScrollView {
                if session.visual.output.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: session.visual.phase == .failed ? "exclamationmark.bubble" : "photo.on.rectangle.angled")
                            .font(.system(size: 23)).foregroundStyle(p.tertiary)
                        Text(title).font(.system(size: 13, weight: .medium))
                        Text(session.visual.notice ?? "选择截图翻译、总结或理解。发送前可核对图片和识别文字。")
                            .font(.system(size: 12)).foregroundStyle(p.secondary).multilineTextAlignment(.center)
                    }.padding(20).frame(maxWidth: .infinity)
                } else {
                    Text(session.visual.output).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
            }.frame(height: 210).frame(maxWidth: .infinity)
                .background(p.canvas, in: RoundedRectangle(cornerRadius: 7))
            HStack {
                if session.visual.isBusy { Button("取消") { session.cancel() } }
                else if session.visual.phase == .failed || session.visual.phase == .cancelled || session.visual.phase == .done {
                    Button("重新确认并重试") { session.retryImage() }.disabled(session.busy)
                }
                Button("复制结果") { session.copyText(session.visual.output) }.disabled(session.visual.phase != .done)
                Button("追问…") { session.openImageFollowup() }.disabled(session.visual.phase != .done)
                Spacer(minLength: 0)
            }.buttonStyle(DesignButtonStyle(variant: .secondary))
            if session.visual.phase == .done {
                Text("追问仅基于本次文字结果；需要原图细节时请重新确认图片。")
                    .font(.system(size: 11)).foregroundStyle(p.secondary)
            }
        }.padding(Tokens.Space.md).background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(p.line, lineWidth: 1))
    }
}
