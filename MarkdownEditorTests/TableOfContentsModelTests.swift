import Combine
import XCTest
@testable import MarkdownEditor

final class TableOfContentsModelTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    private func heading(_ title: String, level: Int, at location: Int)
        -> (range: NSRange, level: Int, title: String) {
        (range: NSRange(location: location, length: title.count), level: level, title: title)
    }

    /// `updateTOC` runs from `textDidChange`, so this is hit on every
    /// keystroke. Typing body text shifts every later heading's character
    /// range but changes nothing the sidebar draws, and re-publishing then
    /// would make SwiftUI re-diff the whole outline for nothing.
    func testShiftingRangesAloneDoesNotRepublishTheOutline() {
        let model = TableOfContentsModel()
        model.update(headings: [heading("Intro", level: 1, at: 0),
                                heading("Details", level: 2, at: 100)])

        var publishCount = 0
        model.objectWillChange.sink { _ in publishCount += 1 }.store(in: &cancellables)

        // Same outline, every range moved — i.e. the user typed above it.
        model.update(headings: [heading("Intro", level: 1, at: 0),
                                heading("Details", level: 2, at: 140)])

        XCTAssertEqual(publishCount, 0, "range-only changes must not re-publish the outline")
        XCTAssertEqual(model.items.map(\.title), ["Intro", "Details"])
    }

    /// ...but a real change to the outline must still land.
    func testChangingAHeadingRepublishes() {
        let model = TableOfContentsModel()
        model.update(headings: [heading("Intro", level: 1, at: 0)])

        var publishCount = 0
        model.objectWillChange.sink { _ in publishCount += 1 }.store(in: &cancellables)

        model.update(headings: [heading("Introduction", level: 1, at: 0)])
        XCTAssertEqual(publishCount, 1)
        XCTAssertEqual(model.items.map(\.title), ["Introduction"])

        model.update(headings: [heading("Introduction", level: 1, at: 0),
                                heading("Appendix", level: 2, at: 200)])
        XCTAssertEqual(publishCount, 2)
        XCTAssertEqual(model.items.count, 2)
    }

    /// Items carry a stable ordinal id rather than a fresh UUID per rebuild,
    /// so `ForEach` keeps row identity across updates instead of tearing the
    /// sidebar down and rebuilding it.
    func testItemIdentityIsStableAcrossRebuilds() {
        let model = TableOfContentsModel()
        model.update(headings: [heading("One", level: 1, at: 0), heading("Two", level: 2, at: 50)])
        let firstIDs = model.items.map(\.id)

        model.update(headings: [heading("One", level: 1, at: 0), heading("Two", level: 2, at: 90)])
        XCTAssertEqual(model.items.map(\.id), firstIDs)
    }

    /// Ranges live outside the published items, so selection has to resolve
    /// against the ranges from the *latest* update, not the ones that were
    /// current when the outline was last published.
    func testSelectionUsesTheLatestRangeEvenWhenTheOutlineDidNotRepublish() {
        let model = TableOfContentsModel()
        model.update(headings: [heading("Intro", level: 1, at: 0),
                                heading("Details", level: 2, at: 100)])

        var selected: NSRange?
        model.onSelect = { selected = $0 }

        // Outline unchanged, ranges moved.
        model.update(headings: [heading("Intro", level: 1, at: 0),
                                heading("Details", level: 2, at: 275)])

        guard let details = model.items.last else { return XCTFail("expected two items") }
        model.select(details)
        XCTAssertEqual(selected?.location, 275)
    }

    /// Defensive: a stale item selected after the document shrank must not
    /// index out of bounds.
    func testSelectingAnItemThatNoLongerExistsIsIgnored() {
        let model = TableOfContentsModel()
        model.update(headings: [heading("One", level: 1, at: 0), heading("Two", level: 2, at: 50)])
        guard let stale = model.items.last else { return XCTFail("expected two items") }

        model.update(headings: [heading("One", level: 1, at: 0)])

        var selected: NSRange?
        model.onSelect = { selected = $0 }
        model.select(stale)
        XCTAssertNil(selected)
    }
}
