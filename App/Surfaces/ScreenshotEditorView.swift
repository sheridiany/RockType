import SwiftUI

struct ScreenshotEditorView: View {
    @State private var model: ScreenshotEditorModel
    @State private var feedback: String?
    @State private var text: String
    let rendering: Bool
    @Environment(\.colorScheme) private var scheme
    init(model: ScreenshotEditorModel, rendering: Bool = false) {
        self.rendering = rendering
        _model = State(initialValue: model)
        _text = State(initialValue: model.recognizedText ?? "")
    }
    private var busy: Bool { model.state == .ocrRunning }
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Label("截图编辑器", systemImage: "viewfinder")
                    .font(Tokens.Typography.font(weight: .medium))
                Spacer()
                Kbd("拖拽框选 · Esc 取消")
            }
            ZStack {
                // Frozen synthetic desktop; surrounding mask uses the existing shadow token.
                p.background
                VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                    Text("示例工作区").font(Tokens.Typography.font(Tokens.Typography.input, weight: .medium))
                    Text("预览笔记与终端输出").foregroundStyle(p.secondary)
                    Spacer()
                }.padding(Tokens.Space.xxl).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                p.windowShadow
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Chip(text: "\(model.pixelWidth) × \(model.pixelHeight)", tone: .accent)
                    ZStack(alignment: .topLeading) {
                        SyntheticCapturePreview(lines: model.imageLines)
                        if !model.annotations.isEmpty {
                            annotationOverlay
                        }
                        if busy {
                            StatusLine(status: .connecting, detail: "正在本机识别文字…")
                                .padding(Tokens.Space.md).background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(height: Tokens.Size.row * 5)
                    .overlay(Rectangle().stroke(p.accent, lineWidth: Tokens.Size.stroke))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: model.state == .selecting ? "plus" : "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(p.accent).padding(Tokens.Space.xs)
                    }
                    .accessibilityLabel("选区，\(model.pixelWidth) 乘 \(model.pixelHeight) 像素")
                    if model.state == .selecting {
                        Text("拖拽选择区域，松开后显示工具栏")
                            .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                        Button("完成框选") { model.state = .selected }
                            .buttonStyle(DesignButtonStyle(variant: .secondary))
                    }
                }
                .padding(.horizontal, Tokens.Space.xxl * 2)
            }
            .frame(height: Tokens.Size.settingsHeight - Tokens.Size.row * 5)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            if model.state != .selecting {
                toolbar
            }
            if model.state == .ocrDone {
                HStack {
                    StatusLine(status: .done, detail: "本机识别 · 未上传")
                    Spacer()
                    Button("复制文字") { feedback = "识别结果已复制" }
                        .buttonStyle(DesignButtonStyle(variant: .secondary))
                }
                Group {
                    if rendering {
                        Text(text).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(Tokens.Space.sm).background(p.pill, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                    } else { DesignTextArea(title: "截图识别结果", text: $text) }
                }.frame(height: Tokens.Size.row * 4)
            }
            if let feedback { Notice(text: feedback) }
        }
        .padding(Tokens.Space.lg).frame(width: Tokens.Size.settingsWidth)
        .modifier(DesignSurface())
        .onExitCommand { feedback = "截图已取消，未保存文件" }
        .accessibilityLabel("截图编辑器 · " + model.state.title)
    }
    private var toolbar: some View {
        let p = Tokens.palette(scheme)
        return HStack(spacing: Tokens.Space.xs) {
            ForEach(ScreenshotEditorModel.Tool.allCases, id: \.self) { tool in
                Button {
                    model.selectedTool = tool
                    model.state = .annotating
                    model.annotations.append(tool)
                    feedback = "已添加" + tool.title + "标注"
                } label: {
                    Image(systemName: tool.symbol).frame(width: Tokens.Size.icon)
                }
                .buttonStyle(DesignButtonStyle(variant: .ghost))
                .background(model.selectedTool == tool ? p.selected : .clear,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                .accessibilityLabel(tool.title).help(tool.title).disabled(busy)
            }
            Rectangle().fill(p.line).frame(width: Tokens.Size.stroke, height: Tokens.Size.compact)
            toolButton("识别文字", "text.viewfinder", disabled: busy) {
                model.state = .ocrDone; text = SurfaceSampleText.ocr; feedback = nil
            }
            toolButton("翻译", "character.bubble", disabled: busy) { feedback = SurfaceSampleText.translation }
            toolButton("撤销", "arrow.uturn.backward", disabled: busy || model.annotations.isEmpty) {
                _ = model.annotations.popLast(); feedback = nil
            }.keyboardShortcut("z")
            Spacer(minLength: 0)
            toolButton("保存", "square.and.arrow.down", disabled: busy) { feedback = "已选择保存（演示不写入文件）" }
                .keyboardShortcut("s")
            toolButton("取消", "xmark") { feedback = "截图已取消，未保存文件" }.keyboardShortcut(.cancelAction)
            Button { feedback = "截图已完成并复制" } label: { Image(systemName: "checkmark") }
                .buttonStyle(DesignButtonStyle(variant: .primary)).disabled(busy)
                .accessibilityLabel("完成并复制").help("完成并复制 ↩").keyboardShortcut(.defaultAction)
        }.padding(Tokens.Space.sm)
            .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .accessibilityElement(children: .contain).accessibilityLabel("标注工具栏")
    }
    private func toolButton(_ title: String, _ symbol: String, disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: Tokens.Size.icon) }
            .buttonStyle(DesignButtonStyle(variant: .ghost)).disabled(disabled)
            .accessibilityLabel(title).help(title)
    }
    private var annotationOverlay: some View {
        let p = Tokens.palette(scheme)
        return ZStack(alignment: .topLeading) {
            if model.annotations.contains(.rectangle) {
                Rectangle().stroke(p.danger, lineWidth: Tokens.Size.focusRing)
                    .padding(.horizontal, Tokens.Space.sm).padding(.top, Tokens.Size.row).padding(.bottom, Tokens.Size.row * 2)
            }
            if model.annotations.contains(.ellipse) {
                Ellipse().stroke(p.danger, lineWidth: Tokens.Size.focusRing)
                    .padding(.horizontal, Tokens.Space.xxl * 3).padding(.vertical, Tokens.Space.xxl)
            }
            HStack(spacing: Tokens.Space.xl) {
                ForEach(Array(model.annotations.enumerated()), id: \.offset) { _, tool in
                    switch tool {
                    case .arrow: Image(systemName: "arrow.up.right").font(Tokens.Typography.font(Tokens.Typography.display))
                    case .number: Text("1").padding(Tokens.Space.xs).background(p.dangerSoft, in: Circle())
                    case .text: Text("检查这里").font(Tokens.Typography.font(weight: .semibold))
                    case .mosaic: Image(systemName: "square.grid.3x3.fill").font(Tokens.Typography.font(Tokens.Typography.display))
                    case .pen: Image(systemName: "scribble").font(Tokens.Typography.font(Tokens.Typography.display))
                    default: EmptyView()
                    }
                }
            }.foregroundStyle(p.danger).padding(.leading, Tokens.Space.xxl).padding(.top, Tokens.Size.row * 3)
        }.allowsHitTesting(false)
    }
}
