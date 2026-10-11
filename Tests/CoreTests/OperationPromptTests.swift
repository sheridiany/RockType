import Foundation
import Testing
@testable import RoarkTCore

@MainActor @Test func customizedPromptsStayAuthoritative() {
    var template = OperationTemplate.defaults[0]
    template.prompt = "Synthetic custom prompt {{target}}"
    #expect(OperationPrompts.resolved(template) == template.prompt)
    #expect(DefaultOperationRunner.targetLanguage("auto", text: "你好 Swift") == "en")
    #expect(DefaultOperationRunner.targetLanguage("auto", text: "Hello Swift") == "zh-Hans")
}
