#if DEBUG
import Foundation

struct VoicePresentation {
    enum State: String, CaseIterable {
        case preparing, recording, silent, recognizing, polishing, done, noSpeech = "no-speech"
        case failed, uncommitted, missingModel = "missing-model"
        var title: String { presentation.title }
        var presentation: RoarkTVoiceHUD.State {
            switch self {
            case .preparing: .preparing
            case .recording, .silent: .recording
            case .recognizing: .processing
            case .polishing: .polishing
            case .done: .success("已填入 · 未发送")
            case .noSpeech: .noSpeech
            case .failed: .notice(title: "识别未完成", detail: "请松开 Fn，再按住重试。")
            case .uncommitted: .result("这是一段合成的识别结果，未填入其他应用。", reason: "输入位置已变化，请复制结果。")
            case .missingModel: .notice(title: "语音模型未下载", detail: "请先在设置 → 语音下载模型。")
            }
        }
    }
    let state: State
    let levels: [Double]
    static func fixture(_ state: State) -> Self {
        Self(state: state, levels: state == .silent ? Array(repeating: 0, count: 9) : [0.2, 0.4, 0.7, 0.95, 0.5, 0.8, 0.6, 0.35, 0.2])
    }
}
#endif
