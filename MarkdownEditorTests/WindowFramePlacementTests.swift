import XCTest
@testable import MarkdownEditor

final class WindowFramePlacementTests: XCTestCase {

    private let saved = NSRect(x: 100, y: 200, width: 900, height: 700)
    private let screen = NSRect(x: 0, y: 0, width: 1800, height: 1100)
    private let offset = WindowFramePlacement.cascadeOffset

    func testFirstWindowGetsSavedFrameUnchanged() {
        let frame = WindowFramePlacement.placement(for: saved, avoiding: [], within: screen)
        XCTAssertEqual(frame, saved)
    }

    /// The multi-file-open regression: the second window must keep the saved
    /// *size* (not fall back to a default) while moving off the first one.
    func testSecondWindowKeepsSavedSizeAndCascades() {
        let frame = WindowFramePlacement.placement(for: saved, avoiding: [saved], within: screen)
        XCTAssertEqual(frame.size, saved.size)
        XCTAssertEqual(frame.minX, saved.minX + offset)
        XCTAssertEqual(frame.maxY, saved.maxY - offset)
    }

    func testThirdWindowCascadesPastBothExisting() {
        let second = saved.offsetBy(dx: offset, dy: -offset)
        let frame = WindowFramePlacement.placement(for: saved, avoiding: [second, saved], within: screen)
        XCTAssertEqual(frame, saved.offsetBy(dx: 2 * offset, dy: -2 * offset))
    }

    /// Only a shared top-left corner counts as stacked — a window elsewhere on
    /// screen, or one already moved by the user, leaves the saved frame alone.
    func testWindowAtDifferentPositionDoesNotTriggerCascade() {
        let elsewhere = saved.offsetBy(dx: 300, dy: 0)
        let frame = WindowFramePlacement.placement(for: saved, avoiding: [elsewhere], within: screen)
        XCTAssertEqual(frame, saved)
    }

    func testNearlyIdenticalCornerCountsAsStacked() {
        let nudged = saved.offsetBy(dx: 1, dy: -1)
        let frame = WindowFramePlacement.placement(for: saved, avoiding: [nudged], within: screen)
        XCTAssertEqual(frame.origin, saved.offsetBy(dx: offset, dy: -offset).origin)
    }

    func testCascadeRunningOffScreenWrapsToTopLeft() {
        let nearEdge = NSRect(x: screen.maxX - saved.width - 10, y: 300, width: saved.width, height: saved.height)
        let frame = WindowFramePlacement.placement(for: nearEdge, avoiding: [nearEdge], within: screen)
        XCTAssertEqual(frame.size, nearEdge.size)
        XCTAssertEqual(frame.minX, screen.minX)
        XCTAssertEqual(frame.maxY, screen.maxY)
    }
}
