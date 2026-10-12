#if DEBUG
import SwiftUI

/// Full-screen capture prototype. The desktop is synthetic; no screen API is used.
struct ScreenshotEditorView: View {
    @State private var model: ScreenshotEditorModel
    @State private var selection: CGRect
    @State private var dragOrigin: CGRect?
    @State private var feedback: String?
    @State private var text: String
    let rendering: Bool
    @Environment(\.colorScheme) private var scheme

    init(model: ScreenshotEditorModel, rendering: Bool = false) {
        self.rendering = rendering
        _model = State(initialValue: model)
        _selection = State(initialValue: model.state == .selected
            ? Tokens.Screenshot.bottomSelection : Tokens.Screenshot.selection)
        _text = State(initialValue: model.recognizedText ?? "")
    }
    private var busy: Bool { model.state == .ocrRunning }
    var body: some View {
        let p = Tokens.palette(scheme)
        ZStack(alignment: .topLeading) {
            frozenDesktop
                .allowsHitTesting(false)
            Path { path in
                path.addRect(CGRect(x: 0, y: 0, width: Tokens.Screenshot.screenWidth, height: Tokens.Screenshot.screenHeight))
                path.addRect(selection)
            }
            .fill(Tokens.Screenshot.mask, style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle().fill(.clear)
                .frame(width: selection.width, height: selection.height)
                .overlay(Rectangle().stroke(p.accent, lineWidth: Tokens.Screenshot.selectionStroke))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: Tokens.Space.xs)
                    .onChanged { value in
                        guard !busy else { return }
                        let origin = dragOrigin ?? selection
                        dragOrigin = origin
                        selection = ScreenshotPlacement.moved(origin, by: value.translation)
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        if model.state == .selecting { model.state = .selected }
                    })
                .position(x: selection.midX, y: selection.midY)
                .accessibilityLabel("选区，\(Int(selection.width)) 乘 \(Int(selection.height)) 像素")

            if !model.annotations.isEmpty {
                annotationOverlay.frame(width: selection.width, height: selection.height)
                    .clipped().position(x: selection.midX, y: selection.midY)
            }
            ForEach(ScreenshotHandle.allCases, id: \.self) { handle in
                let point = handle.point(in: selection)
                Circle().fill(p.card)
                    .overlay(Circle().stroke(p.accent, lineWidth: Tokens.Screenshot.selectionStroke))
                    .frame(width: Tokens.Screenshot.handle, height: Tokens.Screenshot.handle)
                    .padding(Tokens.Space.sm).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !busy else { return }
                            let origin = dragOrigin ?? selection
                            dragOrigin = origin
                            selection = ScreenshotPlacement.resized(origin, handle: handle, by: value.translation)
                        }
                        .onEnded { _ in dragOrigin = nil; if model.state == .selecting { model.state = .selected } })
                    .position(point)
                    .accessibilityLabel("调整选区 · " + handle.title)
            }
            Chip(text: "\(Int(selection.width)) × \(Int(selection.height))", tone: .accent)
                .frame(height: Tokens.Screenshot.badgeHeight)
                .offset(x: selection.minX,
                        y: max(Tokens.Screenshot.edge, selection.minY - Tokens.Screenshot.badgeHeight - Tokens.Space.xs))

            if model.state == .selecting {
                HStack(spacing: Tokens.Space.md) {
                    Kbd("拖动选区或手柄调整 · Esc 取消")
                    Button("完成框选") { model.state = .selected }
                        .buttonStyle(DesignButtonStyle(variant: .secondary))
                }
                .padding(Tokens.Space.sm)
                .background(p.card, in: RoundedRectangle(cornerRadius: 10))
                .position(ScreenshotPlacement.toolbarCenter(for: selection))
            } else {
                toolbar.position(ScreenshotPlacement.toolbarCenter(for: selection))
            }
            if busy || model.state == .ocrDone {
                ocrPanel.position(ScreenshotPlacement.ocrCenter(for: selection, busy: busy))
            }
            if let feedback {
                Notice(text: feedback).frame(width: Tokens.Size.resultWidth)
                    .position(x: Tokens.Screenshot.screenWidth / 2,
                              y: Tokens.Screenshot.screenHeight - Tokens.Screenshot.dockHeight)
            }
        }
        .frame(width: Tokens.Screenshot.screenWidth, height: Tokens.Screenshot.screenHeight)
        .font(Tokens.Typography.font()).foregroundStyle(p.foreground).tint(p.accent)
        .scaleEffect(Tokens.Screenshot.thumbnailScale, anchor: .topLeading)
        .frame(width: Tokens.Screenshot.screenWidth * Tokens.Screenshot.thumbnailScale,
               height: Tokens.Screenshot.screenHeight * Tokens.Screenshot.thumbnailScale, alignment: .topLeading)
        .clipped()
        .onExitCommand { feedback = "截图已取消，未保存文件" }
        .accessibilityLabel("全屏冻结遮罩 · " + model.state.title)
    }

    private var frozenDesktop: some View {
        let p = Tokens.palette(scheme)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [p.screenshotDesktopTop, p.screenshotDesktopBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: Tokens.Space.xl) {
                ScreenshotIcon(systemName: ScreenshotSymbols.desktopApple)
                Text("Finder").font(Tokens.Typography.font(weight: .semibold))
                Text("文件"); Text("编辑"); Text("显示"); Text("窗口"); Text("帮助")
                Spacer()
                ScreenshotIcon(systemName: ScreenshotSymbols.desktopNetwork); ScreenshotIcon(systemName: ScreenshotSymbols.desktopBattery)
                Text("10 月 11 日 周日 16:24")
            }
            .padding(.horizontal, Tokens.Space.lg).frame(height: Tokens.Screenshot.menuHeight)
            .background(p.window)

            VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                HStack(spacing: Tokens.Space.sm) {
                    windowControls
                    Spacer()
                    ScreenshotLabel("预览笔记", systemImage: ScreenshotSymbols.document)
                    Spacer()
                    ScreenshotIcon(systemName: ScreenshotSymbols.sidebar)
                }
                Rectangle().fill(p.line).frame(height: Tokens.Size.hairline)
                HStack(alignment: .top, spacing: Tokens.Space.xxl) {
                    VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                        ScreenshotLabel("所有笔记", systemImage: ScreenshotSymbols.folder)
                        ScreenshotLabel("设计记录", systemImage: ScreenshotSymbols.edit)
                        ScreenshotLabel("已归档", systemImage: ScreenshotSymbols.archive)
                    }.foregroundStyle(p.secondary).frame(width: Tokens.Size.gallerySidebar, alignment: .leading)
                    VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                        Text("让工作留在本机").font(Tokens.Typography.font(Tokens.Typography.display, weight: .semibold))
                        Text("设计记录 / 10 月 11 日").foregroundStyle(p.secondary)
                        Text(SurfaceSampleText.translation).lineSpacing(Tokens.Typography.readingSpacing)
                        Text("本次验证").font(Tokens.Typography.font(Tokens.Typography.input, weight: .medium))
                        ScreenshotLabel("离线时继续编辑", systemImage: ScreenshotSymbols.checked)
                        ScreenshotLabel("保留每一次修改", systemImage: ScreenshotSymbols.checked)
                        ScreenshotLabel("让状态清楚可见", systemImage: ScreenshotSymbols.ellipse)
                        Spacer()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Tokens.Space.xl)
            .frame(width: Tokens.Screenshot.noteWindow.width, height: Tokens.Screenshot.noteWindow.height)
            .background(p.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .shadow(color: p.windowShadow, radius: Tokens.Shadow.windowRadius, y: Tokens.Shadow.windowY)
            .offset(x: Tokens.Screenshot.noteWindow.minX, y: Tokens.Screenshot.noteWindow.minY)

            SyntheticCapturePreview(lines: model.imageLines)
                .frame(width: Tokens.Screenshot.terminalWindow.width, height: Tokens.Screenshot.terminalWindow.height)
                .shadow(color: p.windowShadow, radius: Tokens.Shadow.windowRadius, y: Tokens.Shadow.windowY)
                .offset(x: Tokens.Screenshot.terminalWindow.minX, y: Tokens.Screenshot.terminalWindow.minY)

            VStack(spacing: Tokens.Space.sm) {
                ScreenshotIcon(systemName: ScreenshotSymbols.folder).font(Tokens.Typography.font(Tokens.Typography.display)).foregroundStyle(p.accent)
                Text("设计文稿")
                ScreenshotIcon(systemName: ScreenshotSymbols.richText).font(Tokens.Typography.font(Tokens.Typography.display)).padding(.top, Tokens.Space.xxl)
                Text("预览说明")
            }.frame(width: Tokens.Screenshot.folderWidth)
                .offset(x: Tokens.Screenshot.folderX, y: Tokens.Screenshot.folderY)

            HStack(spacing: Tokens.Space.xxl) {
                ForEach([ScreenshotSymbols.desktopGrid, ScreenshotSymbols.desktopBrowser, ScreenshotSymbols.notes, ScreenshotSymbols.terminal, ScreenshotSymbols.folder, ScreenshotSymbols.delete], id: \.self) { symbol in
                    ScreenshotIcon(systemName: symbol).font(Tokens.Typography.font(Tokens.Typography.display))
                        .foregroundStyle(p.secondary)
                }
            }.frame(width: Tokens.Screenshot.dockWidth, height: Tokens.Screenshot.dockHeight)
                .background(p.window, in: RoundedRectangle(cornerRadius: Tokens.Radius.bubble))
                .position(x: Tokens.Screenshot.screenWidth / 2,
                          y: Tokens.Screenshot.screenHeight - Tokens.Screenshot.dockHeight / 2 - Tokens.Screenshot.edge)
        }
    }
    private var windowControls: some View {
        let p = Tokens.palette(scheme)
        return HStack(spacing: Tokens.Space.sm) {
            ForEach([p.danger, p.warn, p.ok].indices, id: \.self) { index in
                Circle().fill([p.danger, p.warn, p.ok][index])
                    .frame(width: Tokens.Screenshot.windowControls, height: Tokens.Screenshot.windowControls)
            }
        }
    }
    private var ocrPanel: some View {
        let p = Tokens.palette(scheme)
        return VStack(alignment: .leading, spacing: Tokens.Space.md) {
            if busy {
                ScreenshotLabel("本机识别中…", systemImage: ScreenshotSymbols.ocr).foregroundStyle(p.accent)
                Text("文字在本机处理，图片未上传。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
            } else {
                HStack {
                    Text("识别结果").font(Tokens.Typography.font(weight: .semibold))
                    Spacer()
                    Chip(text: "本机 · 未上传", tone: .ok)
                }
                if rendering {
                    Text(text).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(Tokens.Space.sm).background(p.pill, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                } else {
                    DesignTextArea(title: "截图识别结果", text: $text)
                }
                HStack {
                    Text("可直接修改").font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                    Spacer()
                    Button("复制文字") { feedback = "识别结果已复制" }
                        .buttonStyle(DesignButtonStyle(variant: .primary))
                }
            }
        }
        .padding(Tokens.Space.lg)
        .frame(width: Tokens.Screenshot.ocrWidth,
               height: busy ? Tokens.Screenshot.ocrBusyHeight : Tokens.Screenshot.ocrHeight)
        .modifier(DesignSurface())
        .shadow(color: p.windowShadow, radius: Tokens.Shadow.secondaryRadius, y: Tokens.Shadow.secondaryY)
    }
    private var toolbar: some View {
        let p = Tokens.palette(scheme)
        return HStack(spacing: Tokens.Space.xs) {
            ForEach(ScreenshotEditorModel.Tool.allCases, id: \.self) { tool in
                Button {
                    model.selectedTool = tool; model.state = .annotating
                    model.annotations.append(tool); feedback = nil
                } label: { ScreenshotIcon(systemName: tool.symbol).frame(width: Tokens.Size.icon) }
                .buttonStyle(ScreenshotIconButtonStyle(selected: model.selectedTool == tool))
                .accessibilityLabel(tool.title).help(tool.title).disabled(busy)
            }
            Rectangle().fill(p.line).frame(width: Tokens.Size.stroke, height: Tokens.Size.compact)
            toolButton("识别文字", ScreenshotSymbols.ocr, disabled: busy) {
                model.state = .ocrDone; text = SurfaceSampleText.ocr; feedback = nil
            }
            toolButton("翻译", ScreenshotSymbols.translate, disabled: busy) { feedback = SurfaceSampleText.translation }
            toolButton("撤销", ScreenshotSymbols.undo, disabled: busy || model.annotations.isEmpty) {
                _ = model.annotations.popLast(); feedback = nil
            }.keyboardShortcut("z")
            Spacer(minLength: 0)
            toolButton("保存", ScreenshotSymbols.save, disabled: busy) { feedback = "已选择保存（演示不写入文件）" }.keyboardShortcut("s")
            toolButton("取消", ScreenshotSymbols.cancel) { feedback = "截图已取消，未保存文件" }.keyboardShortcut(.cancelAction)
            Button { feedback = "截图已完成并复制" } label: { ScreenshotIcon(systemName: ScreenshotSymbols.complete) }
                .buttonStyle(ScreenshotIconButtonStyle(primary: true)).disabled(busy)
                .accessibilityLabel("完成并复制").help("完成并复制 ↩").keyboardShortcut(.defaultAction)
        }
        .padding(Tokens.Space.sm)
        .frame(width: Tokens.Screenshot.toolbarWidth, height: Tokens.Screenshot.toolbarHeight)
        .background(p.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.line, lineWidth: Tokens.Size.hairline))
        .shadow(color: p.windowShadow, radius: Tokens.Shadow.secondaryRadius, y: Tokens.Shadow.secondaryY)
        .accessibilityElement(children: .contain).accessibilityLabel("标注工具栏")
    }
    private func toolButton(_ title: String, _ symbol: String, disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { ScreenshotIcon(systemName: symbol).frame(width: Tokens.Size.icon) }
            .buttonStyle(ScreenshotIconButtonStyle()).disabled(disabled)
            .accessibilityLabel(title).help(title)
    }
    private var annotationOverlay: some View {
        let p = Tokens.palette(scheme)
        return ZStack(alignment: .topLeading) {
            if model.annotations.contains(.rectangle) {
                Rectangle().stroke(p.danger, lineWidth: Tokens.Size.focusRing)
                    .padding(.horizontal, Tokens.Space.xxl).padding(.top, Tokens.Size.row * 2).padding(.bottom, Tokens.Size.row * 3)
            }
            if model.annotations.contains(.ellipse) {
                Ellipse().stroke(p.danger, lineWidth: Tokens.Size.focusRing)
                    .padding(.horizontal, Tokens.Space.xxl * 3).padding(.vertical, Tokens.Space.xxl)
            }
            HStack(spacing: Tokens.Space.xl) {
                ForEach(Array(model.annotations.enumerated()), id: \.offset) { _, tool in
                    switch tool {
                    case .arrow: ScreenshotIcon(systemName: ScreenshotSymbols.arrow).font(Tokens.Typography.font(Tokens.Typography.display))
                    case .number: Text("1").padding(Tokens.Space.xs).background(p.dangerSoft, in: Circle())
                    case .text: Text("检查这里").font(Tokens.Typography.font(weight: .semibold))
                    case .mosaic: ScreenshotIcon(systemName: ScreenshotSymbols.mosaic).font(Tokens.Typography.font(Tokens.Typography.display))
                    case .pen: ScreenshotIcon(systemName: ScreenshotSymbols.pen).font(Tokens.Typography.font(Tokens.Typography.display))
                    default: EmptyView()
                    }
                }
            }.foregroundStyle(p.danger).padding(.leading, Tokens.Space.xxl * 2).padding(.top, Tokens.Size.row * 6)
        }.allowsHitTesting(false)
    }
}

enum ScreenshotPlacement {
    static func toolbarCenter(for rect: CGRect) -> CGPoint {
        let width = Tokens.Screenshot.toolbarWidth, height = Tokens.Screenshot.toolbarHeight
        let edge = Tokens.Screenshot.edge, gap = Tokens.Screenshot.gap
        let below = rect.maxY + gap
        let y = below + height <= Tokens.Screenshot.screenHeight - edge ? below : rect.minY - gap - height
        return CGPoint(x: min(max(rect.maxX - width / 2, edge + width / 2), Tokens.Screenshot.screenWidth - edge - width / 2),
                       y: max(edge + height / 2, y + height / 2))
    }
    static func ocrCenter(for rect: CGRect, busy: Bool) -> CGPoint {
        let width = Tokens.Screenshot.ocrWidth
        let height = busy ? Tokens.Screenshot.ocrBusyHeight : Tokens.Screenshot.ocrHeight
        let edge = Tokens.Screenshot.edge, gap = Tokens.Screenshot.gap
        let right = rect.maxX + gap
        let x = right + width <= Tokens.Screenshot.screenWidth - edge ? right : rect.minX - gap - width
        return CGPoint(x: max(edge + width / 2, x + width / 2),
                       y: min(max(edge + height / 2, rect.minY + height / 2), Tokens.Screenshot.screenHeight - edge - height / 2))
    }
    static func moved(_ rect: CGRect, by delta: CGSize) -> CGRect {
        CGRect(x: min(max(0, rect.minX + delta.width), Tokens.Screenshot.screenWidth - rect.width),
               y: min(max(0, rect.minY + delta.height), Tokens.Screenshot.screenHeight - rect.height),
               width: rect.width, height: rect.height)
    }
    static func resized(_ rect: CGRect, handle: ScreenshotHandle, by delta: CGSize) -> CGRect {
        let minimum = Tokens.Screenshot.minimumSelection
        var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
        if handle.movesLeft { left = min(max(0, left + delta.width), right - minimum) }
        if handle.movesRight { right = max(min(Tokens.Screenshot.screenWidth, right + delta.width), left + minimum) }
        if handle.movesTop { top = min(max(0, top + delta.height), bottom - minimum) }
        if handle.movesBottom { bottom = max(min(Tokens.Screenshot.screenHeight, bottom + delta.height), top + minimum) }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

#endif
