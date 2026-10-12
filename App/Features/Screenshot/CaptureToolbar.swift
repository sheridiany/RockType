import SwiftUI
import RoarkTCore

struct CaptureToolbar: View {
    let tool: ScreenshotTool?
    let style: ScreenshotAnnotationStyle
    let changeStyle: (ScreenshotAnnotationStyle) -> Void
    let canUndo: Bool
    let canRedo: Bool
    let select: (ScreenshotTool?) -> Void
    let undo: () -> Void
    let redo: () -> Void
    let cancel: () -> Void
    let complete: () -> Void
    let preview: () -> Void
    var pinningEnabled = true
    @Environment(\.colorScheme) private var scheme
    private let colors = ["D84A2F", "F2B824", "40A578", "388BEB", "9B6DDF", "FFFFFF", "202124"]

    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        toolButton(symbol: ScreenshotSymbols.select, title: "选择标注 / 调整选区 · V", selected: tool == nil) { select(nil) }
                        ForEach(ScreenshotTool.allCases, id: \.self) { item in
                            toolButton(symbol: item.symbol, title: "\(item.title) · \(item.shortcut)" + (item == .text ? " · 双击编辑 · ↩ 换行 · Esc 提交" : ""), selected: tool == item) { select(item) }
                        }
                        Divider().frame(height: 20)
                        action(ScreenshotSymbols.undo, "撤销 ⌘Z", undo).disabled(!canUndo)
                        action(ScreenshotSymbols.redo, "重做 ⇧⌘Z", redo).disabled(!canRedo)
                    }.padding(.horizontal, 2)
                }
                Divider().frame(height: 20)
                action(ScreenshotSymbols.ocr, "预览、OCR、翻译与保存", preview)
                action(ScreenshotSymbols.cancel, "取消 Esc", cancel)
                toolButton(symbol: ScreenshotSymbols.complete, title: "复制 ↩ / ⌘C · 另存为 ⌘S · 保存路径 ⇧↩ · OCR ⇧C" + (pinningEnabled ? " · P 贴图" : ""), selected: false, primary: true, action: complete)
            }

            Divider()
            HStack(spacing: 8) {
                if let tool {
                    if tool != .mosaic && tool != .eraser {
                        ForEach(colors, id: \.self) { hex in
                            Button {
                                var next = style; next.colorHex = hex; changeStyle(next)
                            } label: {
                                Circle().fill(Color(nsColor: ScreenshotAnnotationStyle(colorHex: hex).nsColor))
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().strokeBorder(.gray.opacity(0.5), lineWidth: 0.5))
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(style.colorHex.uppercased() == hex ? p.foreground : .clear, lineWidth: 1.5))
                            }.buttonStyle(.plain).help("颜色 #\(hex)").accessibilityLabel("颜色 #\(hex)")
                        }
                        Divider().frame(height: 18)
                    }
                    Text(tool == .text ? "字号" : tool == .mosaic ? "颗粒" : "粗细").foregroundStyle(p.secondary)
                    Slider(value: Binding(get: { style.width }, set: { value in
                        var next = style; next.width = value.rounded(); changeStyle(next)
                    }), in: tool.widthRange, step: 1).frame(width: 86).accessibilityLabel(tool == .text ? "字号" : tool == .mosaic ? "颗粒" : "粗细")
                    Text("\(Int(style.width))").monospacedDigit().frame(width: 24, alignment: .trailing)
                    if tool == .text {
                        Toggle("背景", isOn: Binding(get: { style.textBackground == true }, set: { enabled in
                            var next = style; next.textBackground = enabled; changeStyle(next)
                        }))
                        .toggleStyle(.button)
                        .help("使用所选颜色作背景，文字自动切换为黑色或白色")
                        .accessibilityLabel("文字标注背景")
                    }
                    Spacer(minLength: 0)
                    Text(tool == .eraser ? "拖动擦除 · 滚轮调大小 · ⌘Z 撤销" : "滚轮调节 · ⇧ 约束 · ⌥ 叠画").foregroundStyle(p.secondary)
                } else {
                    Text("双击空白处复制 · 点击标注编辑 · ⌫ 删除 · ⌥/⌘ 方向键调边")
                        .foregroundStyle(p.secondary)
                    Spacer(minLength: 0)
                }
            }.font(.system(size: 11)).frame(height: 26).padding(.horizontal, 6)
        }
        .padding(8).background(p.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .foregroundStyle(p.foreground)
    }
    private func toolButton(symbol: String, title: String, selected: Bool, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { ScreenshotIcon(systemName: symbol) }
            .buttonStyle(ScreenshotIconButtonStyle(selected: selected, primary: primary))
            .help(title).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func action(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        toolButton(symbol: symbol, title: title, selected: false, action: action)
    }
}
