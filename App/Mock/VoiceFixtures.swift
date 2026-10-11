import Foundation

struct VoicePresentation {
    enum State: String, CaseIterable {
        case recording, recognizing, done, failed, cancelled, missingModel = "missing-model"
        var title: String {
            switch self {
            case .recording: "录音中"
            case .recognizing: "正在识别"
            case .done: "已填入 · 未发送"
            case .failed: "识别未完成"
            case .cancelled: "已取消"
            case .missingModel: "语音模型未下载"
            }
        }
        var symbol: String {
            switch self {
            case .recording: "mic.fill"
            case .recognizing: "ellipsis"
            case .done: "checkmark"
            case .failed: "exclamationmark.circle"
            case .cancelled: "xmark"
            case .missingModel: "arrow.down.circle"
            }
        }
    }
    let state: State
    let elapsed: String
    let levels: [Double]
    let detail: String
    static func fixture(_ state: State) -> Self {
        Self(state: state, elapsed: "0:08", levels: [0.2, 0.4, 0.7, 0.95, 0.5, 0.8, 0.6, 0.35, 0.2],
             detail: state == .failed ? "没有识别出文字。请松开 Fn，再按住重新录音；本次录音不会保留。" :
                state == .missingModel ? "先在设置 → 语音下载模型。下载完成前不会开启麦克风。" : "")
    }
}
