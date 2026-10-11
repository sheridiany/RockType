import Foundation

/// Synthetic copy only. This is a rendering fixture, not an AI request/session model.
struct ResultExample {
    let status: ResultStatus
    let source: String
    let result: String
    let detail: String

    static let streaming = ResultExample(
        status: .streaming,
        source: "Small tools can make everyday work feel lighter.",
        result: "小巧的工具，可以让日常工作",
        detail: "示例模型 · 首字 0.3 秒"
    )
    static let done = ResultExample(
        status: .done,
        source: "Small tools can make everyday work feel lighter.",
        result: "小巧的工具，可以让日常工作更轻松。\n\n让注意力留在内容上，让工具安静地完成它的工作。",
        detail: "示例模型 · 1.2 秒"
    )
}
