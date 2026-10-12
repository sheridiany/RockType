import AppKit
import XCTest
@testable import RoarkTApp

final class ScreenshotSymbolsTests: XCTestCase {
    @MainActor func testCatalogSymbolsResolveAndAreAvailableOnMacOS14() throws {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
        // Apple's catalog is verification input only; the application has no dependency on this file.
        let data = try Data(contentsOf: url)
        let catalog = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let symbols = try XCTUnwrap(catalog["symbols"] as? [String: String])
        let releases = try XCTUnwrap(catalog["year_to_release"] as? [String: [String: String]])
        for name in ScreenshotSymbols.all {
            XCTAssertNotNil(ScreenshotSymbols.image(name), "Missing glyph: \(name)")
            let year = try XCTUnwrap(symbols[name], name)
            let version = try XCTUnwrap(releases[year]?["macOS"], name)
            XCTAssertTrue(version.compare("14.0", options: .numeric) != .orderedDescending, "\(name) requires \(version)")
        }
    }
}
