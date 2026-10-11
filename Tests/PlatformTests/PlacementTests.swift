import XCTest
@testable import RoarkTPlatform

final class PlacementTests: XCTestCase {
    func testMigratedRulesAndRightEdge() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let cases: [(CGRect?, Placement.Rule)] = [
            (CGRect(x: 100, y: 200, width: 300, height: 20), .below),
            (CGRect(x: 100, y: 700, width: 300, height: 20), .above), (nil, .cursor)
        ]
        for (selection, rule) in cases {
            let result = Placement.floating(selection: selection, cursor: CGPoint(x: 500, y: 400),
                                            size: CGSize(width: 420, height: 480), screen: screen)
            XCTAssertEqual(result.rule, rule)
            XCTAssertTrue(screen.insetBy(dx: 12, dy: 12).contains(CGRect(origin: result.origin, size: CGSize(width: 420, height: 480))))
        }
        XCTAssertEqual(Placement.floating(selection: CGRect(x: 1400, y: 100, width: 30, height: 18),
                                         cursor: .zero, size: CGSize(width: 420, height: 480), screen: screen).origin.x, 1008)
    }

    func testRightAndEdgeAndPanel() {
        let screen = CGRect(x: -1000, y: 0, width: 1000, height: 600)
        let size = CGSize(width: 420, height: 480)
        XCTAssertEqual(Placement.floating(selection: CGRect(x: -950, y: 250, width: 30, height: 20), cursor: .zero, size: size, screen: screen).rule, .right)
        XCTAssertEqual(Placement.floating(selection: CGRect(x: -400, y: 250, width: 30, height: 20), cursor: .zero, size: size, screen: screen).rule, .edge)
        XCTAssertEqual(Placement.panel(width: 420, screen: screen), CGPoint(x: -710, y: 132))
    }

    @MainActor func testCoordinatesOnDisplayAbovePrimary() {
        XCTAssertEqual(ScreenGeometry.topLeft(CGRect(x: -800, y: 900, width: 800, height: 600), primaryHeight: 900),
                       CGRect(x: -800, y: -600, width: 800, height: 600))
        XCTAssertEqual(ScreenGeometry.topLeft(CGPoint(x: -400, y: 1000), primaryHeight: 900), CGPoint(x: -400, y: -100))
    }
}
