import Cocoa
import Security

// This policy only authorizes quitting an input method during replacement.
// It must never be used to authorize XPC operations or access to user data.
enum RoarkTProcessTrust {
  static func canTerminate(_ application: NSRunningApplication, replacement: Bundle) -> Bool {
    guard let identifier = replacement.bundleIdentifier,
          identifier == Identifiers.inputMethodBundleID,
          application.bundleIdentifier == identifier,
          let executable = replacement.executableURL?.resolvingSymlinksInPath().standardizedFileURL,
          application.executableURL?.resolvingSymlinksInPath().standardizedFileURL == executable else { return false }

    var code: SecCode?
    let attributes = [kSecGuestAttributePid: NSNumber(value: application.processIdentifier)] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
          let code else { return false }
    var requirement: SecRequirement?
    let text = Identifiers.codeRequirement(for: identifier)
    guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
          let requirement else { return false }
    return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
  }
}
