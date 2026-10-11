struct ImagePreviewModel: Sendable {
    enum State: String, CaseIterable, Sendable {
        case preview, ocrRunning, ocrDone, ocrEmpty, noVision, noPermission, clipboard, drop
        var title: String {
            switch self {
            case .preview: "预览"
            case .ocrRunning: "OCR 进行中"
            case .ocrDone: "OCR 完成 · 可编辑"
            case .ocrEmpty: "未识别到文字"
            case .noVision: "视觉模型不可用"
            case .noPermission: "屏幕录制权限缺失"
            case .clipboard: "剪贴板图片"
            case .drop: "拖入图片"
            }
        }
    }
    var state: State
    var origin: String
    var pixelWidth: Int
    var pixelHeight: Int
    var imageLines: [String]
    var recognizedText: String
    var hasImage: Bool { state != .noPermission }
    var visionAvailable: Bool { state != .noVision }
    static let samples: [SurfaceSample<Self>] = State.allCases.map {
        .init(id: $0.rawValue, title: $0.title, value: .init(state: $0,
            origin: $0 == .clipboard ? "剪贴板图片" : $0 == .drop ? "拖入图片" : "截图",
            pixelWidth: 1284, pixelHeight: 356,
            imageLines: $0 == .noPermission ? [] : SurfaceSampleText.imageLines,
            recognizedText: $0 == .ocrDone ? SurfaceSampleText.ocr : ""))
    }
}
