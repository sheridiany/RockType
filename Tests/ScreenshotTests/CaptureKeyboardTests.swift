import AppKit
import XCTest
@testable import RoarkTApp

final class CaptureKeyboardTests: XCTestCase {
    func testCChordsReturnToolsAndSaveRemainDisjoint() {
        func map(_ code: UInt16, _ text: String, _ flags: NSEvent.ModifierFlags = []) -> CaptureKeyCommand? {
            CaptureKeyboard.command(keyCode: code, characters: text, modifiers: flags)
        }
        XCTAssertEqual(map(8, "c"), .copyColor)
        XCTAssertEqual(map(8, "C", .shift), .ocrCopy)
        XCTAssertEqual(map(8, "c", .command), .copy)
        XCTAssertNil(map(8, "c", [.command, .shift]))
        XCTAssertEqual(map(1, "s", .command), .saveAs)
        XCTAssertEqual(map(36, "\r", .shift), .quickSave)
        XCTAssertEqual(map(36, "\r"), .copy)
        XCTAssertEqual(map(18, "!", .shift), .tool(.rectangle))
        XCTAssertEqual(map(28, "*", .shift), .tool(.text))
        XCTAssertEqual(map(25, "(", .shift), .tool(.number))
        XCTAssertEqual(map(6, "Z", [.shift, .command]), .redo)
        XCTAssertEqual(map(14, "e"), .tool(.eraser))
        XCTAssertEqual(map(9, "v"), .tool(nil))
        XCTAssertEqual(map(35, "p"), .pin)
        XCTAssertEqual(map(15, "r"), .restore)
        XCTAssertEqual(map(51, ""), .delete)
        XCTAssertEqual(map(117, ""), .delete)
        XCTAssertNil(map(18, "1", .control))
        XCTAssertNil(map(8, "c", .option))
    }
    func testArrowModifiersHaveOneMeaning() {
        XCTAssertEqual(CaptureKeyboard.command(keyCode: 123, characters: nil, modifiers: []), .nudge(.left, nil, fast: false))
        XCTAssertEqual(CaptureKeyboard.command(keyCode: 125, characters: nil, modifiers: [.option, .shift]), .nudge(.down, .leading, fast: true))
        XCTAssertEqual(CaptureKeyboard.command(keyCode: 124, characters: nil, modifiers: .command), .nudge(.right, .trailing, fast: false))
        // Undeclared arrow modifier combinations retain the old movement fallback.
        XCTAssertEqual(CaptureKeyboard.command(keyCode: 126, characters: nil, modifiers: [.command, .option]), .nudge(.up, nil, fast: false))
        XCTAssertEqual(CaptureKeyboard.command(keyCode: 126, characters: nil, modifiers: .control), .nudge(.up, nil, fast: false))
        XCTAssertEqual(CaptureKeyboard.command(keyCode: 6, characters: "z", modifiers: [.command, .option]), .undo)
    }
    func testEdgesKeepOppositeSideFixedAndCannotInvertOrEscape() {
        let rect = CGRect(x: 20, y: 30, width: 80, height: 60)
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 150)
        let left = CaptureGeometry.nudged(rect, direction: .left, edge: .leading, step: 10, bounds: bounds)
        XCTAssertEqual(left.minX, 10); XCTAssertEqual(left.maxX, rect.maxX)
        let top = CaptureGeometry.nudged(rect, direction: .up, edge: .leading, step: 100, bounds: bounds)
        XCTAssertEqual(top.minY, 0); XCTAssertEqual(top.maxY, rect.maxY)
        let right = CaptureGeometry.nudged(rect, direction: .right, edge: .trailing, step: 500, bounds: bounds)
        XCTAssertEqual(right.minX, rect.minX); XCTAssertEqual(right.maxX, 200)
        let bottom = CaptureGeometry.nudged(rect, direction: .up, edge: .trailing, step: 500, bounds: bounds)
        XCTAssertEqual(bottom.minY, rect.minY); XCTAssertEqual(bottom.height, 1)
        XCTAssertEqual(CaptureGeometry.nudged(.zero, direction: .right, edge: .trailing, step: 1, bounds: bounds), .zero)
    }
    func testToolbarMovesAboveSelectionAtBottomOfScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 700)
        let selection = CGRect(x: 200, y: 400, width: 500, height: 280)
        let toolbar = CaptureGeometry.toolbarFrame(selection: selection, bounds: bounds)
        XCTAssertLessThan(toolbar.maxY, selection.minY)
        XCTAssertTrue(bounds.contains(toolbar))
    }
}
