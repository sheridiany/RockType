#if DEBUG
struct ScreenshotEditorModel: Sendable {
    enum State: String, CaseIterable, Sendable {
        case selecting, selected, annotating, ocrRunning, ocrDone
        var title: String {
            switch self {
            case .selecting: "框选中 · 显示尺寸"
            case .selected: "已选区 · 工具栏"
            case .annotating: "标注中"
            case .ocrRunning: "OCR 中"
            case .ocrDone: "OCR 完成"
            }
        }
    }
    enum Tool: String, CaseIterable, Sendable {
        case rectangle, ellipse, arrow, pen, mosaic, text, number
        var title: String {
            switch self {
            case .rectangle: "矩形"
            case .ellipse: "椭圆"
            case .arrow: "箭头"
            case .pen: "画笔"
            case .mosaic: "马赛克"
            case .text: "文字"
            case .number: "序号"
            }
        }
        var symbol: String {
            switch self {
            case .rectangle: ScreenshotSymbols.rectangle
            case .ellipse: ScreenshotSymbols.ellipse
            case .arrow: ScreenshotSymbols.arrow
            case .pen: ScreenshotSymbols.pen
            case .mosaic: ScreenshotSymbols.mosaic
            case .text: ScreenshotSymbols.text
            case .number: ScreenshotSymbols.number
            }
        }
    }
    var state: State
    var pixelWidth: Int
    var pixelHeight: Int
    var selectedTool: Tool?
    var annotations: [Tool]
    var imageLines: [String]
    var recognizedText: String?
    static let samples: [SurfaceSample<Self>] = State.allCases.map {
        .init(id: $0.rawValue, title: $0.title, value: .init(state: $0, pixelWidth: 1284,
            pixelHeight: 356, selectedTool: $0 == .annotating ? .arrow : nil,
            annotations: $0 == .annotating ? [.rectangle, .arrow, .number] : [],
            imageLines: SurfaceSampleText.imageLines,
            recognizedText: $0 == .ocrDone ? SurfaceSampleText.ocr : nil))
    }
}

#endif
