import XCTest
@testable import MarkdownEditor

final class MarkdownStyleMapTests: XCTestCase {

    private func text(_ range: NSRange, in source: String) -> String {
        (source as NSString).substring(with: range)
    }

    func testEmptyDocumentProducesNoElements() {
        let map = MarkdownStyleMap(text: "")
        XCTAssertTrue(map.elements.isEmpty)
        XCTAssertTrue(map.allDelimiterRanges.isEmpty)
        XCTAssertTrue(map.checkboxes.isEmpty)
        XCTAssertTrue(map.headings.isEmpty)
    }

    // MARK: - Inline delimiters

    func testBoldDelimiterRanges() {
        let source = "Hello **world** end"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: { text($0.contentRange, in: source) == "world" }) else {
            return XCTFail("no bold element found")
        }
        XCTAssertEqual(el.delimiterRanges.count, 2)
        XCTAssertEqual(text(el.delimiterRanges[0], in: source), "**")
        XCTAssertEqual(text(el.delimiterRanges[1], in: source), "**")
    }

    func testItalicDelimiterRanges() {
        let source = "Hello _world_ end"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: { text($0.contentRange, in: source) == "world" }) else {
            return XCTFail("no italic element found")
        }
        XCTAssertEqual(el.delimiterRanges.map { text($0, in: source) }, ["_", "_"])
    }

    /// Regression: single-tilde strikethrough ("~x~") used to have its delimiter
    /// ranges sized for "~~", eating the first/last real character.
    func testStrikethroughSingleTilde() {
        let source = "before ~gone~ after"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: {
            $0.attributes[.strikethroughStyle] != nil
        }) else {
            return XCTFail("no strikethrough element found")
        }
        XCTAssertEqual(text(el.contentRange, in: source), "gone")
        XCTAssertEqual(el.delimiterRanges.map { text($0, in: source) }, ["~", "~"])
    }

    func testStrikethroughDoubleTilde() {
        let source = "before ~~gone~~ after"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: {
            $0.attributes[.strikethroughStyle] != nil
        }) else {
            return XCTFail("no strikethrough element found")
        }
        XCTAssertEqual(text(el.contentRange, in: source), "gone")
        XCTAssertEqual(el.delimiterRanges.map { text($0, in: source) }, ["~~", "~~"])
    }

    func testInlineCodeDelimiters() {
        let source = "run `swift build` now"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: { text($0.contentRange, in: source) == "swift build" }) else {
            return XCTFail("no inline code element found")
        }
        XCTAssertEqual(el.delimiterRanges.map { text($0, in: source) }, ["`", "`"])
    }

    func testLinkBracketsAndURL() {
        let source = "See [the docs](https://example.com) here"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: { text($0.contentRange, in: source) == "the docs" }) else {
            return XCTFail("no link element found")
        }
        XCTAssertEqual(el.delimiterRanges.count, 2)
        XCTAssertEqual(text(el.delimiterRanges[0], in: source), "[")
        XCTAssertEqual(text(el.delimiterRanges[1], in: source), "](https://example.com)")
        XCTAssertEqual(el.attributes[.markdownLinkURL] as? String, "https://example.com")
    }

    // MARK: - Headings

    func testATXHeadingDelimiterAndContent() {
        let source = "## Section Title\nbody"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: { text($0.contentRange, in: source) == "Section Title" }) else {
            return XCTFail("no ATX heading element found")
        }
        XCTAssertEqual(el.delimiterRanges.count, 1)
        XCTAssertEqual(text(el.delimiterRanges[0], in: source), "## ")
        XCTAssertEqual(map.headings.count, 1)
        XCTAssertEqual(map.headings[0].level, 2)
        XCTAssertEqual(map.headings[0].title, "Section Title")
    }

    /// Regression: Setext headings ("Text\n===") must hide only the underline
    /// line, keeping the text line itself visible and unstyled as a delimiter.
    func testSetextHeadingHidesOnlyUnderline() {
        let source = "Heading\n===\nbody\n"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.headings.count, 1)
        XCTAssertEqual(map.headings[0].level, 1)
        XCTAssertEqual(map.headings[0].title, "Heading")

        guard let el = map.elements.first(where: { $0.delimiterRanges.count == 1 }) else {
            return XCTFail("no setext heading element found")
        }
        XCTAssertEqual(text(el.contentRange, in: source).trimmingCharacters(in: .whitespacesAndNewlines), "Heading")
        XCTAssertEqual(text(el.delimiterRanges[0], in: source).trimmingCharacters(in: .whitespacesAndNewlines), "===")
        // Regression: swift-markdown reports the Heading node's own range as
        // extending into the very next block when there's no blank line
        // between the underline and what follows it — if MarkdownStyleMap
        // trusted that upper bound, the heading's fullRange (and therefore
        // its bold/large font) would swallow "body" too, and "body" would
        // also get hidden as a bogus part of the delimiter.
        XCTAssertEqual(text(el.fullRange, in: source).trimmingCharacters(in: .whitespacesAndNewlines), "Heading\n===")
        XCTAssertFalse(map.allDelimiterRanges.contains { text($0, in: source).contains("body") })
    }

    // MARK: - Blockquotes

    /// Regression: lazy-continuation lines (no leading "> " of their own but
    /// still part of the quote) must not get a colored marker of their own,
    /// while every line that does start with "> " must.
    func testBlockquoteMarkerRangesIncludingLazyContinuation() {
        let source = "> line one\nlazy continuation\n> line three\n"
        let map = MarkdownStyleMap(text: source)
        let markerTexts = map.elements
            .filter { $0.attributes.keys.contains(where: { $0 == .foregroundColor }) && $0.fullRange.length <= 2 }
            .map { text($0.fullRange, in: source) }
        XCTAssertEqual(markerTexts.filter { $0.hasPrefix(">") }.count, 2, "expected exactly 2 marker lines, not the lazy-continuation line")
    }

    // MARK: - Checkboxes

    func testCheckboxBracketsUncheckedAndChecked() {
        let source = "- [ ] todo\n- [x] done\n"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.checkboxes.count, 2)
        XCTAssertEqual(map.checkboxes[0].checked, false)
        XCTAssertEqual(text(map.checkboxes[0].range, in: source), "[ ]")
        XCTAssertEqual(map.checkboxes[1].checked, true)
        XCTAssertEqual(text(map.checkboxes[1].range, in: source), "[x]")
    }

    // MARK: - List bullet depth glyphs

    func testUnorderedBulletGlyphCyclesByDepth() {
        let source = "- top\n  - nested\n"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.listMarkerGlyphOverrides.count, 2)
        XCTAssertEqual(map.listMarkerGlyphOverrides[0].character, "\u{25CF}") // ●
        XCTAssertEqual(map.listMarkerGlyphOverrides[1].character, "\u{25CB}") // ○
    }

    // MARK: - Tables

    func testTableColumnPaddingKernsShortCells() {
        // Column 0 cells are "Name"/"Bo" (deficit 2 on "Bo"); column 1 cells
        // are "Info"/"**Bold**" whose 4 hidden delimiter chars make both
        // cells' *visual* width 4, so no padding is needed there.
        let source = "| Name | Info |\n| --- | --- |\n| Bo | **Bold** |\n"
        let map = MarkdownStyleMap(text: source)

        XCTAssertEqual(map.tableRegions.count, 1)
        XCTAssertGreaterThan(map.tableRegions[0].requiredWidth, 0)

        let charWidth = MarkdownTheme.shared.codeFont.maximumAdvancement.width
        let kernElements = map.elements.filter { $0.attributes[.kern] != nil }
        // "Name" (deficit 0, +1 pipe) and "Bo" (deficit 2, +1 pipe) both pad;
        // the last column never pads since there's no trailing pipe to offset.
        let kernValues = kernElements
            .compactMap { $0.attributes[.kern] as? CGFloat }
            .sorted()
        XCTAssertEqual(kernValues.count, 2)
        XCTAssertEqual(kernValues[0], 1 * charWidth, accuracy: 0.01) // "Name": deficit 0, +1 pipe
        XCTAssertEqual(kernValues[1], 3 * charWidth, accuracy: 0.01) // "Bo": deficit 2, +1 pipe
    }

    func testHeadingsCollectedInDocumentOrderForTOC() {
        let source = "# One\n\n## Two\n\n### Three\n"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.headings.map(\.title), ["One", "Two", "Three"])
        XCTAssertEqual(map.headings.map(\.level), [1, 2, 3])
    }
}
