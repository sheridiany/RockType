/// Single source of identifiers for Swift code. Mirrors Shared/XPCProtocol/include/RoarkTIdentifiers.h.
public enum Identifiers {
    public static let teamID = "DF7J2VBQD8"
    public static let appBundleID = "com.roarkist.roarkt"
    public static let inputMethodBundleID = "com.roarkist.inputmethod.RoarkT"
    public static let pinyinInputSourceID = "com.roarkist.inputmethod.RoarkT.pinyin"
    public static let flypyInputSourceID = "com.roarkist.inputmethod.RoarkT.flypy"
    public static let translationServiceName = "com.roarkist.roarkt.translation"
    public static let voiceWorkerID = "com.roarkist.roarkt.voice"
    public static let dictationEndpointName = "com.roarkist.inputmethod.RoarkT.dictation"
    public static let keychainService = "com.roarkist.roarkt.ai"
    public static let applicationSupportFolder = "RoarkT"

    /// Code requirement for an XPC peer with the given signing identifier.
    public static func codeRequirement(for identifier: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(identifier)\""
    }
}
