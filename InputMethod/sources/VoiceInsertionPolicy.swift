// Input-method-owned insertion gate. See LICENSE.translation.txt.
import Foundation

enum VoiceInsertionPolicy {
  static func allowsAutomaticInsertion(text: String, applicationID: String?) -> Bool {
    guard let applicationID, !applicationID.isEmpty, !text.isEmpty,
          text.rangeOfCharacter(from: .controlCharacters) == nil,
          text.rangeOfCharacter(from: .newlines) == nil else { return false }
    return true
  }
}
