import Foundation
import CryptoKit

/// Builds a single-release feed for a signed product pkg. Never handles private keys.
enum AppcastDocument {
    enum Failure: Error { case invalidMetadata, invalidSignature }

    static func render(package: Data, info: [String: Any], download: String, signature: String) throws -> String {
        guard let version = info["CFBundleShortVersionString"] as? String,
              version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              let build = info["CFBundleVersion"] as? String, let number = UInt64(build), number > 0,
              let minimum = info["LSMinimumSystemVersion"] as? String,
              minimum.range(of: #"^[0-9]+\.[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let url = URL(string: download), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.contains("/releases/download/"), url.path.hasSuffix(".pkg"), !download.contains("REPLACE_"),
              let publicKey = info["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: publicKey),
              let signatureData = Data(base64Encoded: signature) else { throw Failure.invalidMetadata }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        guard key.isValidSignature(signatureData, for: package) else { throw Failure.invalidSignature }
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>RockType</title>
            <description>RockType for macOS</description>
            <language>zh-CN</language>
            <item>
              <title>RockType \(escape(version))</title>
              <sparkle:version>\(build)</sparkle:version>
              <sparkle:shortVersionString>\(escape(version))</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>\(escape(minimum))</sparkle:minimumSystemVersion>
              <enclosure url="\(escape(download))" length="\(package.count)" type="application/octet-stream"
                sparkle:os="macos" sparkle:installationType="guided-package" sparkle:edSignature="\(escape(signature))" />
            </item>
          </channel>
        </rss>
        """
    }
}
