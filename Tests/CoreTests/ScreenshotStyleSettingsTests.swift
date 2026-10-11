import Foundation
import XCTest
@testable import RoarkTCore

final class ScreenshotStyleSettingsTests: XCTestCase {
    func testMissingStylesDecodeAndPreferencesRoundTripWithoutContent() throws {
        let data = Data(#"{"format":"png","ocrLanguages":["zh-Hans","en-US"]}"#.utf8)
        var settings = try JSONDecoder().decode(ScreenshotSettings.self, from: data)
        XCTAssertNil(settings.annotationStyles)
        XCTAssertEqual(settings.format, .png)
        settings.annotationStyles = ["arrow": .init(colorHex: "388BEB", width: 9), "text": .init(width: 17)]
        let encoded = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(ScreenshotSettings.self, from: encoded), settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let styles = try XCTUnwrap(object["annotationStyles"] as? [String: [String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(styles["arrow"]).keys), ["colorHex", "width"])
    }
}
