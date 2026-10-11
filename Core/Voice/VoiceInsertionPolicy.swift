// Shared MIT insertion gate. See LICENSE.md.
import Foundation

public enum VoiceInsertionPolicy {
  public static func allowsAutomaticInsertion(text: String, applicationID: String?) -> Bool {
    guard let applicationID, !applicationID.isEmpty, !text.isEmpty,
          text.rangeOfCharacter(from: .controlCharacters) == nil,
          text.rangeOfCharacter(from: .newlines) == nil else { return false }
    return true
  }
}
