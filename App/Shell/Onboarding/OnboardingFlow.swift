import Observation

/// Owns navigation, never grants permission or enables an input source.
@MainActor @Observable
final class OnboardingFlow {
    enum Resolution { case completed, skipped }
    private(set) var step: OnboardingStep = .input
    private(set) var resolutions: [OnboardingStep: Resolution] = [:]
    private(set) var finished = false
    private(set) var errorMessage: String?
    private let store: SettingsStore

    init(store: SettingsStore) { self.store = store }
    var shouldPresentAutomatically: Bool { !store.settings.general.onboardingCompleted }

    func select(_ step: OnboardingStep) { self.step = step; errorMessage = nil }

    func resolve(_ resolution: Resolution) {
        resolutions[step] = resolution
        if let next = OnboardingStep.allCases.first(where: { resolutions[$0] == nil }) {
            step = next
        } else {
            finish()
        }
    }

    func restart() {
        step = .input
        resolutions = [:]
        finished = false
        errorMessage = nil
    }

    private func finish() {
        let previous = store.settings.general.onboardingCompleted
        store.settings.general.onboardingCompleted = true
        store.flush()
        guard store.persistenceError == nil else {
            store.settings.general.onboardingCompleted = previous
            errorMessage = "无法保存引导状态，请检查磁盘空间与文件权限后重试。"
            return
        }
        finished = true
    }
}
