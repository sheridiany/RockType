import Foundation
import CryptoKit
import Testing
@testable import RoarkTApp

@Test func appcastVerifiesPackageAgainstEmbeddedPublicKey() throws {
    let key = Curve25519.Signing.PrivateKey()
    let package = Data("synthetic package for signature verification".utf8)
    let signature = try key.signature(for: package).base64EncodedString()
    let info: [String: Any] = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "2",
                               "LSMinimumSystemVersion": "14.0", "SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString()]
    let download = "https://github.com/example/project/releases/download/v0.1.0/RoarkT.pkg"
    let xml = try AppcastDocument.render(package: package, info: info, download: download, signature: signature)
    #expect(xml.contains("sparkle:installationType=\"guided-package\""))
    #expect(xml.contains("<sparkle:version>2</sparkle:version>"))
    #expect(xml.contains("length=\"\(package.count)\""))
    #expect(throws: (any Error).self) {
        try AppcastDocument.render(package: package + Data([0]), info: info, download: download, signature: signature)
    }
    var wrongKey = info
    wrongKey["SUPublicEDKey"] = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
    #expect(throws: (any Error).self) {
        try AppcastDocument.render(package: package, info: wrongKey, download: download, signature: signature)
    }
    for invalid in ["http://github.com/example/project/releases/download/v1/a.pkg", "https://github.com/REPLACE_OWNER/project/releases/download/v1/a.pkg", "https://untrusted.example/a.pkg"] {
        #expect(throws: (any Error).self) {
            try AppcastDocument.render(package: package, info: info, download: invalid, signature: signature)
        }
    }
}

@MainActor @Test func updaterRejectsUnconfiguredFeedBeforeStartingSparkle() {
    let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
    #expect(!UpdateController.configurationReady([:]))
    #expect(!UpdateController.configurationReady(["SUFeedURL": "https://github.com/REPLACE_OWNER/REPLACE_REPO/releases/latest/download/appcast.xml", "SUPublicEDKey": key]))
    #expect(!UpdateController.configurationReady(["SUFeedURL": "https://github.com/example/project/releases/latest/download/appcast.xml", "SUPublicEDKey": "placeholder"]))
    #expect(UpdateController.configurationReady(["SUFeedURL": "https://github.com/example/project/releases/latest/download/appcast.xml", "SUPublicEDKey": key]))
}
