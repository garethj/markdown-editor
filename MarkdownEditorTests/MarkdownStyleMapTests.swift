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

    func testAsteriskItalicDelimiterRanges() {
        let source = "Hello *world* end"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: { text($0.contentRange, in: source) == "world" }) else {
            return XCTFail("no asterisk-italic element found")
        }
        XCTAssertEqual(el.delimiterRanges.map { text($0, in: source) }, ["*", "*"])
    }

    /// CommonMark: a single asterisk can open/close emphasis mid-word, but a
    /// single underscore cannot — it's treated as a literal character there.
    func testIntraWordAsteriskEmphasisWorks() {
        let source = "He*ll*o"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: { text($0.contentRange, in: source) == "ll" }) else {
            return XCTFail("expected mid-word asterisk emphasis to parse as italic")
        }
        XCTAssertEqual(el.delimiterRanges.map { text($0, in: source) }, ["*", "*"])
    }

    func testIntraWordUnderscoreDoesNotEmphasize() {
        let source = "He_ll_o"
        let map = MarkdownStyleMap(text: source)
        XCTAssertTrue(map.elements.isEmpty, "CommonMark: underscores mid-word must not trigger emphasis")
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

    // MARK: - Nested / combined emphasis

    func testItalicWithNestedBold() {
        let source = "_text **bold** text_"
        let map = MarkdownStyleMap(text: source)
        guard let italicEl = map.elements.first(where: {
            $0.delimiterRanges.map({ text($0, in: source) }) == ["_", "_"]
        }) else {
            return XCTFail("no italic element found")
        }
        XCTAssertEqual(text(italicEl.contentRange, in: source), "text **bold** text")

        guard let boldEl = map.elements.first(where: { text($0.contentRange, in: source) == "bold" }) else {
            return XCTFail("no nested bold element found")
        }
        XCTAssertEqual(boldEl.delimiterRanges.map { text($0, in: source) }, ["**", "**"])
    }

    func testBoldWithNestedItalic() {
        let source = "**text _italic_ text**"
        let map = MarkdownStyleMap(text: source)
        guard let boldEl = map.elements.first(where: {
            $0.delimiterRanges.map({ text($0, in: source) }) == ["**", "**"]
        }) else {
            return XCTFail("no bold element found")
        }
        XCTAssertEqual(text(boldEl.contentRange, in: source), "text _italic_ text")

        guard let italicEl = map.elements.first(where: { text($0.contentRange, in: source) == "italic" }) else {
            return XCTFail("no nested italic element found")
        }
        XCTAssertEqual(italicEl.delimiterRanges.map { text($0, in: source) }, ["_", "_"])
    }

    /// Regression: "***text***" gives Strong and Emphasis the *same*
    /// reported fullRange (swift-markdown doesn't split the run into tidy
    /// nested sub-ranges for this ambiguous triple-delimiter case). Letting
    /// each side independently hide its own fixed-width delimiter from that
    /// shared range's edges used to double-count one edge character and
    /// leave the innermost asterisk on each side visible as literal text.
    /// The AST parent of the pair now claims the full 3-character run on
    /// each side instead, and the nested child claims none — so between the
    /// two elements, all six asterisks (three per side) are accounted for
    /// exactly once, and both a bold- and an italic-attributed element
    /// still exist over the correctly-trimmed content.
    func testTripleAsteriskCombinesBoldAndItalic() {
        let source = "***bold italic***"
        let map = MarkdownStyleMap(text: source)
        let matching = map.elements.filter { text($0.fullRange, in: source) == source }
        XCTAssertEqual(matching.count, 2, "expected both a bold-wrapping and an italic-wrapping element")
        XCTAssertTrue(matching.allSatisfy { text($0.contentRange, in: source) == "bold italic" })

        guard let boldEl = matching.first(where: { $0.attributes[.font] as? NSFont == MarkdownTheme.shared.boldFont }) else {
            return XCTFail("no bold element found")
        }
        guard let italicEl = matching.first(where: { $0.attributes[.font] as? NSFont == MarkdownTheme.shared.italicFont }) else {
            return XCTFail("no italic element found")
        }

        // Exactly one of the pair is the AST parent and claims all three
        // asterisks on each side; the other claims none. Which one is
        // "outer" is a parser detail, so check the pair jointly rather than
        // assuming which specific element (bold or italic) it'll be.
        let delimiterOwners = [boldEl, italicEl].filter { !$0.delimiterRanges.isEmpty }
        XCTAssertEqual(delimiterOwners.count, 1, "expected exactly one of the pair to own the delimiters")
        XCTAssertEqual(delimiterOwners[0].delimiterRanges.map { text($0, in: source) }, ["***", "***"])
    }

    // MARK: - Code blocks

    /// Documents current behavior: despite the comment in
    /// `visitCodeBlock` claiming fence lines are hidden as delimiters,
    /// `delimiterRanges` is actually empty — the fences remain visible,
    /// styled with the code font along with the rest of the block. If that
    /// comment reflects the intended behavior rather than the code, this
    /// test is the one to update alongside a real fix.
    func testFencedCodeBlockFencesRemainVisible() {
        let source = "```\nlet x = 1\n```\n"
        let map = MarkdownStyleMap(text: source)
        guard let el = map.elements.first(where: {
            $0.attributes[.foregroundColor] as? NSColor == MarkdownTheme.shared.codeColor
        }) else {
            return XCTFail("no code block element found")
        }
        XCTAssertEqual(el.delimiterRanges, [])
        XCTAssertEqual(el.contentRange, el.fullRange)
        XCTAssertTrue(text(el.fullRange, in: source).hasPrefix("```"))
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

    /// A heading's own text can itself contain inline emphasis markup — the
    /// heading delimiter and the nested emphasis delimiter are independent
    /// elements and both must be tracked.
    func testATXHeadingWithNestedItalic() {
        let source = "## _Section_\nbody"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.headings.first?.title, "Section")

        guard let italicEl = map.elements.first(where: {
            text($0.contentRange, in: source) == "Section" &&
            $0.delimiterRanges.map({ text($0, in: source) }) == ["_", "_"]
        }) else {
            return XCTFail("expected a nested italic element inside the heading")
        }
        _ = italicEl
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

    /// A checked task's own text should be dimmed (greyed out but still
    /// readable) so a completed task visibly recedes; an unchecked task's
    /// text should be left at the normal default color.
    func testCheckedTaskTextIsDimmedButUncheckedTaskTextIsNormal() {
        let source = "- [ ] todo\n- [x] done\n"
        let map = MarkdownStyleMap(text: source)
        let dimmedColor = MarkdownTheme.shared.checkedTaskTextAttributes[.foregroundColor] as? NSColor
        XCTAssertNotNil(dimmedColor)

        let uncheckedTextIsDimmed = map.elements.contains {
            text($0.fullRange, in: source).contains("todo")
                && ($0.attributes[.foregroundColor] as? NSColor) == dimmedColor
        }
        XCTAssertFalse(uncheckedTextIsDimmed, "unchecked task's text must not be dimmed")

        let checkedTextIsDimmed = map.elements.contains {
            text($0.fullRange, in: source).contains("done")
                && ($0.attributes[.foregroundColor] as? NSColor) == dimmedColor
        }
        XCTAssertTrue(checkedTextIsDimmed, "checked task's text must be dimmed")
    }

    /// Unchecked boxes use the same accent color as bullets/links; checked
    /// boxes use the dimmed color rather than the old green checkmark color.
    func testCheckboxBracketColorsMatchTheme() {
        let source = "- [ ] todo\n- [x] done\n"
        let map = MarkdownStyleMap(text: source)
        let bracketElements = map.elements.filter { $0.fullRange.length == 3 && text($0.fullRange, in: source).hasPrefix("[") }
        XCTAssertEqual(bracketElements.count, 2)

        let uncheckedColor = bracketElements[0].attributes[.foregroundColor] as? NSColor
        let checkedColor = bracketElements[1].attributes[.foregroundColor] as? NSColor
        XCTAssertEqual(uncheckedColor, MarkdownTheme.shared.linkColor)
        XCTAssertEqual(checkedColor, MarkdownTheme.shared.checkedTaskTextAttributes[.foregroundColor] as? NSColor)
    }

    // MARK: - List bullet depth glyphs

    func testUnorderedBulletGlyphCyclesByDepth() {
        let source = "- top\n  - nested\n    - deeper\n      - deepest\n"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.listMarkerGlyphOverrides.count, 4)
        XCTAssertEqual(map.listMarkerGlyphOverrides[0].character, "\u{25CF}") // ●
        XCTAssertEqual(map.listMarkerGlyphOverrides[1].character, "\u{25CB}") // ○
        // Depths 3+ must resolve to glyphs .AppleSystemUIFont actually has at
        // the bullet's small point size — the geometric-shapes diamonds
        // (◆ U+25C6 / ◇ U+25C7) have none there, so the layout-manager glyph
        // substitution silently no-ops and the literal "-" source marker
        // draws instead. This regressed once already; assert the
        // diamond-suit glyphs (which do resolve) explicitly rather than just
        // asserting "not equal to the source marker".
        XCTAssertEqual(map.listMarkerGlyphOverrides[2].character, "\u{2666}") // ♦
        XCTAssertEqual(map.listMarkerGlyphOverrides[3].character, "\u{2662}") // ♢
        for override in map.listMarkerGlyphOverrides {
            XCTAssertNotEqual(override.character, "\u{25C6}", "◆ has no glyph in .AppleSystemUIFont at the bullet size")
            XCTAssertNotEqual(override.character, "\u{25C7}", "◇ has no glyph in .AppleSystemUIFont at the bullet size")
        }
    }

    /// Nested inline formatting inside a list item's text must not disturb
    /// the item's own bullet-marker handling.
    func testBoldWithNestedItalicInsideListItem() {
        let source = "- **Keyboard _shortcuts_**: Cmd+B for bold\n"
        let map = MarkdownStyleMap(text: source)
        guard let boldEl = map.elements.first(where: { text($0.contentRange, in: source) == "Keyboard _shortcuts_" }) else {
            return XCTFail("no bold element found in list item")
        }
        XCTAssertEqual(boldEl.delimiterRanges.map { text($0, in: source) }, ["**", "**"])

        guard let italicEl = map.elements.first(where: { text($0.contentRange, in: source) == "shortcuts" }) else {
            return XCTFail("no nested italic element found in list item")
        }
        XCTAssertEqual(italicEl.delimiterRanges.map { text($0, in: source) }, ["_", "_"])

        XCTAssertEqual(map.listMarkerGlyphOverrides.count, 1)
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
        // Excludes the separator row's own kern elements (covered by
        // testSeparatorRowPipesAlignWithColumns) so this only asserts on
        // real-cell kerning, as it always has.
        let sepLineRange = (source as NSString).range(of: "| --- | --- |")
        let kernElements = map.elements.filter {
            $0.attributes[.kern] != nil && NSIntersectionRange($0.fullRange, sepLineRange).length == 0
        }
        // "Name" (deficit 0, +1 pipe) and "Bo" (deficit 2, +1 pipe) both pad;
        // the last column never pads since there's no trailing pipe to offset.
        let kernValues = kernElements
            .compactMap { $0.attributes[.kern] as? CGFloat }
            .sorted()
        XCTAssertEqual(kernValues.count, 2)
        XCTAssertEqual(kernValues[0], 1 * charWidth, accuracy: 0.01) // "Name": deficit 0, +1 pipe
        XCTAssertEqual(kernValues[1], 3 * charWidth, accuracy: 0.01) // "Bo": deficit 2, +1 pipe
    }

    /// Italic (not just bold) inside a table cell must also count its hidden
    /// delimiter chars toward the cell's visual width, or column alignment
    /// drifts for any table with italic content.
    func testTableCellWithItalicAccountsForHiddenDelimitersInWidth() {
        // Column 1: "Status" (6 chars, header) vs "_Away_" (6 raw chars, 2
        // hidden underscores -> visual width 4, deficit 2). It's the last
        // column, so no +1 pipe compensation. Column 0 is the same "Name"/
        // "Bo" case as the bold-cell test above.
        let source = "| Name | Status |\n| --- | --- |\n| Bo | _Away_ |\n"
        let map = MarkdownStyleMap(text: source)

        let charWidth = MarkdownTheme.shared.codeFont.maximumAdvancement.width
        // Excludes the separator row's own kern elements (covered by
        // testSeparatorRowPipesAlignWithColumns) so this only asserts on
        // real-cell kerning, as it always has.
        let sepLineRange = (source as NSString).range(of: "| --- | --- |")
        let kernValues = map.elements
            .filter { NSIntersectionRange($0.fullRange, sepLineRange).length == 0 }
            .compactMap { $0.attributes[.kern] as? CGFloat }
            .sorted()
        XCTAssertEqual(kernValues.count, 3)
        XCTAssertEqual(kernValues[0], 1 * charWidth, accuracy: 0.01) // "Name": deficit 0, +1 pipe
        XCTAssertEqual(kernValues[1], 2 * charWidth, accuracy: 0.01) // "_Away_": deficit 2, last column
        XCTAssertEqual(kernValues[2], 3 * charWidth, accuracy: 0.01) // "Bo": deficit 2, +1 pipe
    }

    /// Pipes and the separator row must never be hidden — no element covering
    /// them should carry delimiterRanges, unlike inline markers (**, _, etc.)
    /// which are hidden until the cursor enters their span.
    func testTablePipesAndSeparatorAreNeverHiddenDelimiters() {
        let source = "| Name | Info |\n| --- | --- |\n| Bo | Hi |\n"
        let map = MarkdownStyleMap(text: source)

        XCTAssertTrue(map.allDelimiterRanges.isEmpty,
                       "table pipes/separator must not be hideable delimiters")

        // Sanity check the source actually contains a separator row and pipes,
        // so this test would fail if the parse silently dropped the table.
        XCTAssertTrue(source.contains("---"))
        XCTAssertEqual(source.filter { $0 == "|" }.count, 9)
    }

    /// Pipes and the separator row are colored with the accent (same as
    /// blockquote markers/links/bullets) so table structure reads without
    /// needing the cursor inside it.
    func testTablePipesAndSeparatorAreAccentColored() {
        let source = "| Name | Info |\n| --- | --- |\n| Bo | Hi |\n"
        let map = MarkdownStyleMap(text: source)

        let accent = MarkdownTheme.shared.linkColor
        let coloredRanges = map.elements.filter {
            ($0.attributes[.foregroundColor] as? NSColor) == accent
        }
        XCTAssertFalse(coloredRanges.isEmpty)

        // Every colored range's text must be made up of pipe/separator
        // characters only (|, -, :, spaces) — never real cell content.
        let allowed = CharacterSet(charactersIn: "|-: \n")
        for element in coloredRanges {
            let snippet = text(element.contentRange, in: source)
            XCTAssertTrue(snippet.unicodeScalars.allSatisfy(allowed.contains),
                          "unexpected non-pipe/separator text colored: \(snippet)")
        }

        // The separator row itself must be fully covered by colored ranges.
        let sepRange = (source as NSString).range(of: "| --- | --- |")
        guard sepRange.location != NSNotFound else {
            return XCTFail("separator row not found in source")
        }
        let coveredLength = coloredRanges.reduce(0) { sum, el in
            sum + NSIntersectionRange(el.contentRange, sepRange).length
        }
        XCTAssertEqual(coveredLength, sepRange.length)
    }

    /// Regression: cursor-reveal (updateCursorReveal in
    /// MarkdownTextView.Coordinator) binary-searches `elements` assuming it's
    /// sorted by fullRange.location. Table visiting breaks that on its own if
    /// `elements` isn't explicitly re-sorted afterward: it appends its own
    /// whole-table/kern/header/pipe-color bookkeeping elements before
    /// descending into cell content, so a Strong/Emphasis element nested in
    /// an earlier cell ends up appended (and thus positioned) after
    /// bookkeeping elements for later cells it actually precedes in the
    /// document — which silently broke clicking into "**Lead**" revealing
    /// its delimiters, since the search could look in the wrong place.
    func testElementsAreSortedByLocationWithNestedFormattingInTable() {
        let source = "| Name | Role | Status |\n| --- | --- | --- |\n" +
            "| Alice | Engineer | Active |\n| Charlie | **Lead** | _Away_ |\n"
        let map = MarkdownStyleMap(text: source)

        let locations = map.elements.map { $0.fullRange.location }
        XCTAssertEqual(locations, locations.sorted(),
                       "elements must be sorted by fullRange.location for cursor-reveal's binary search")

        guard let boldEl = map.elements.first(where: { text($0.contentRange, in: source) == "Lead" }) else {
            return XCTFail("no bold element found for table cell 'Lead'")
        }
        XCTAssertEqual(boldEl.delimiterRanges.map { text($0, in: source) }, ["**", "**"])
    }

    /// The separator row has no AST cell structure of its own, so its
    /// dash/colon runs must be individually kerned (like real cells) or its
    /// pipes drift out of alignment with the rest of the table.
    func testSeparatorRowPipesAlignWithColumns() {
        let source = "| Name | Info |\n| --- | --- |\n| Alice | Hi |\n"
        let map = MarkdownStyleMap(text: source)
        let charWidth = MarkdownTheme.shared.codeFont.maximumAdvancement.width

        // Column 0: " Name " (6, padding included — real Table.Cell.range
        // includes its own padding, so the separator's segment must be
        // compared against that same convention) vs " Alice " (7) -> max 7.
        // Separator's untrimmed " --- " segment (5) needs deficit 2, +1 for
        // the inter-column pipe.
        let sepRowRange = (source as NSString).range(of: "| --- | --- |")
        let kernInSepRow = map.elements
            .filter { $0.attributes[.kern] != nil && NSIntersectionRange($0.fullRange, sepRowRange).length > 0 }
            .sorted { $0.fullRange.location < $1.fullRange.location }
        guard let firstColumnKern = kernInSepRow.first else {
            return XCTFail("no kern element found for separator row's first column")
        }
        let kernValue = firstColumnKern.attributes[.kern] as? CGFloat
        XCTAssertEqual(kernValue ?? -1, 3 * charWidth, accuracy: 0.01)
    }

    /// Regression: widening the separator row (e.g. typing extra dashes)
    /// must widen the whole column to match, not just leave the separator
    /// sticking out past real cells that were never re-padded to compensate.
    func testWideningSeparatorRowPullsRealCellsAlongWithIt() {
        // Column 0's separator " ------- " (9, padding included) is wider
        // than either real cell " A " (3) or " x " (3) — the column's max
        // width must come from the separator, not just real cell content.
        let source = "| A | B |\n| ------- | --- |\n| x | y |\n"
        let map = MarkdownStyleMap(text: source)
        let charWidth = MarkdownTheme.shared.codeFont.maximumAdvancement.width

        // Cell ranges include their own padding (" A ", not "A"), and kern
        // lands on the last character of that padded range.
        let aCellRange = (source as NSString).range(of: " A ")
        let aKernEl = map.elements.first {
            $0.attributes[.kern] != nil && NSMaxRange($0.fullRange) == NSMaxRange(aCellRange)
        }
        guard let aKernValue = aKernEl?.attributes[.kern] as? CGFloat else {
            return XCTFail("no kern element found for cell \"A\"")
        }
        // max(3, 3, 9) = 9; deficit = 9 - 3 = 6, +1 for the inter-column pipe.
        XCTAssertEqual(aKernValue, 7 * charWidth, accuracy: 0.01)
    }

    func testHeadingsCollectedInDocumentOrderForTOC() {
        let source = "# One\n\n## Two\n\n### Three\n"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.headings.map(\.title), ["One", "Two", "Three"])
        XCTAssertEqual(map.headings.map(\.level), [1, 2, 3])
    }
}
