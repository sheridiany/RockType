import XCTest
@testable import RoarkTPlatform

final class SelectionRangeTests: XCTestCase {
    @MainActor func testWebViewEmptySelectedTextUsesExactUTF16Range() {
        let result = SelectionTextResolution.read(readable: { true }, selected: { "" },
            range: { CFRange(location: 15, length: 3) }, string: { range in
                XCTAssertEqual(range.location, 15); XCTAssertEqual(range.length, 3)
                return "😀a"
            }, attributed: { _ in XCTFail("Should not read twice"); return nil })
        XCTAssertEqual(result.status, .success); XCTAssertEqual(result.text, "😀a")
    }
    @MainActor func testAttributedRangeFallbackAndWholeDocumentRejection() {
        let result = SelectionTextResolution.read(readable: { true }, selected: { nil },
            range: { CFRange(location: 5, length: 3) }, string: { _ in "entire synthetic document" },
            attributed: { _ in "abc" })
        XCTAssertEqual(result.text, "abc")
    }
    @MainActor func testInvalidEmptyHugeAndOverflowRangesNeverReadDocument() {
        for range in [CFRange(location: -1, length: 1), CFRange(location: 0, length: 65_537),
                      CFRange(location: Int.max, length: 2), CFRange(location: 0, length: 0)] {
            let result = SelectionTextResolution.read(readable: { true }, selected: { nil }, range: { range },
                string: { _ in XCTFail("Invalid selection"); return nil }, attributed: { _ in XCTFail("Invalid selection"); return nil })
            XCTAssertEqual(result.status, range.length == 0 ? .empty : .unsupported)
        }
    }
    @MainActor func testProtectionAfterRangeReadDiscardsTextAndDoesNotTryNextPath() {
        var allowed = true
        let result = SelectionTextResolution.read(readable: { allowed }, selected: { nil },
            range: { CFRange(location: 0, length: 3) }, string: { _ in allowed = false; return "abc" },
            attributed: { _ in XCTFail("Protected"); return nil })
        XCTAssertEqual(result.status, .secureInput); XCTAssertNil(result.text)
    }
}
