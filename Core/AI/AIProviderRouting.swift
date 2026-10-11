import Foundation

public enum AITask: String, Codable, CaseIterable, Sendable {
    case translation, assistant, image, inputAI
    public var title: String {
        switch self {
        case .translation: "翻译"
        case .assistant: "总结、润色、解释与追问"
        case .image: "图片"
        case .inputAI: "输入法内 AI"
        }
    }
}

public enum AIProviderRouting {
    public struct Resolved: Equatable, Sendable {
        public let connection: AIConnectionSettings
        public let model: String
    }
    public static let recommendedModel = "workbuddy/glm-5.3-flash"
    public static let suggestedFallback = "claude/claude-haiku-5-5"

    public static func providers(_ settings: AppSettings) -> [AIConnectionSettings] {
        var seen = Set<String>()
        return ([settings.ai] + (settings.aiProviders ?? [])).filter { seen.insert($0.id).inserted }
    }

    /// A dangling task selection fails closed; it never sends to another provider by accident.
    public static func resolve(_ settings: AppSettings, task: AITask, modelOverride: String? = nil) throws -> Resolved {
        let route = settings.aiTaskRoutes?[task.rawValue]
        guard let connection = providers(settings).first(where: { $0.id == (route?.providerID ?? settings.ai.id) }) else {
            throw AIClientError.configuration
        }
        let inherited: String?
        if let route { inherited = nonempty(route.model) ?? (task == .image ? connection.visionModel : nil) }
        else {
            switch task {
            case .translation: inherited = settings.translation.model
            case .assistant: inherited = settings.selection.assistantModel
            case .image: inherited = connection.visionModel
            case .inputAI: inherited = nil
            }
        }
        let model = nonempty(modelOverride) ?? nonempty(inherited) ?? connection.defaultModel
        guard nonempty(model) != nil else { throw AIClientError.configuration }
        return Resolved(connection: connection, model: model)
    }

    /// Swap the chosen profile into the existing default connection field; no credentials are copied.
    public static func select(_ id: String, in settings: inout AppSettings) {
        let all = providers(settings)
        guard let selected = all.first(where: { $0.id == id }) else { return }
        settings.ai = selected
        settings.aiProviders = all.filter { $0.id != id }
    }

    public static func remove(_ id: String, from settings: inout AppSettings) {
        guard id != settings.ai.id else { return }
        settings.aiProviders?.removeAll { $0.id == id }
        // Keep dangling routes visible and fail closed until the user explicitly reassigns them.
    }

    public static func fallback(for connection: AIConnectionSettings, primary: String, error: Error,
                                hasVisibleOutput: Bool) -> String? {
        guard !hasVisibleOutput, let fallback = nonempty(connection.fallbackModel), fallback != primary,
              let error = error as? AIClientError else { return nil }
        switch error {
        case .network, .timeout, .server, .rateLimited, .emptyResponse, .modelNotFound: return fallback
        default: return nil
        }
    }
    public static func nonempty(_ text: String?) -> String? {
        guard let text else { return nil }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
