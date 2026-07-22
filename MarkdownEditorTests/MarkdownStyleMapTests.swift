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

    /// Regression: an ATX heading's optional closing sequence of #s (e.g.
    /// "# Heading #", valid CommonMark) used to render as plain, un-hidden,
    /// unstyled trailing text — swift-markdown's heading.range already
    /// excludes it (the same way it excludes trailing whitespace before it),
    /// so MarkdownStyleMap never even saw it as part of the heading, let
    /// alone hid it the way the leading "# " is hidden.
    func testATXHeadingClosingSequenceIsHidden() {
        let source = "# Heading using #\nbody"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.headings.count, 1)
        XCTAssertEqual(map.headings[0].title, "Heading using")

        guard let el = map.elements.first(where: { text($0.contentRange, in: source) == "Heading using" }) else {
            return XCTFail("no ATX heading element found")
        }
        XCTAssertEqual(el.delimiterRanges.map { text($0, in: source) }, ["# ", " #"])
        // The closing sequence must not leak into the next line's styling.
        XCTAssertFalse(text(el.fullRange, in: source).contains("body"))
    }

    /// A closing sequence is only valid when the rest of the line, after the
    /// #s, is nothing but whitespace — trailing text that merely starts with
    /// "#" must stay part of the visible heading content.
    func testATXHeadingTrailingHashWithoutValidClosingSequenceStaysVisible() {
        let source = "# Heading #not-a-closer\nbody"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.headings[0].title, "Heading #not-a-closer")
        guard let el = map.elements.first(where: { text($0.contentRange, in: source) == "Heading #not-a-closer" }) else {
            return XCTFail("no ATX heading element found")
        }
        XCTAssertEqual(el.delimiterRanges.map { text($0, in: source) }, ["# "])
    }

    /// Setext headings ("Text\n===") show the underline in the accent color
    /// rather than hiding it. Unlike ATX's "#" (pure noise once font size
    /// signals the level), "==="/"---" is the only thing distinguishing an H1
    /// from an H2 in that syntax — so, like a blockquote's ">" or a table's
    /// pipes, it stays visible, just recolored.
    func testSetextHeadingUnderlineIsVisibleAndAccentColored() {
        let source = "Heading\n===\nbody\n"
        let map = MarkdownStyleMap(text: source)
        XCTAssertEqual(map.headings.count, 1)
        XCTAssertEqual(map.headings[0].level, 1)
        XCTAssertEqual(map.headings[0].title, "Heading")

        guard let headingEl = map.elements.first(where: {
            text($0.contentRange, in: source).trimmingCharacters(in: .whitespacesAndNewlines) == "Heading"
        }) else {
            return XCTFail("no setext heading content element found")
        }
        XCTAssertTrue(headingEl.delimiterRanges.isEmpty, "the underline must not be hidden as a delimiter")
        // Regression: swift-markdown reports the Heading node's own range as
        // extending into the very next block when there's no blank line
        // between the underline and what follows it — if MarkdownStyleMap
        // trusted that upper bound, the heading's fullRange (and therefore
        // its bold/large font) would swallow "body" too.
        XCTAssertEqual(text(headingEl.fullRange, in: source).trimmingCharacters(in: .whitespacesAndNewlines), "Heading\n===")

        guard let underlineEl = map.elements.first(where: {
            text($0.fullRange, in: source).trimmingCharacters(in: .whitespacesAndNewlines) == "==="
        }) else {
            return XCTFail("no setext underline overlay element found")
        }
        XCTAssertEqual(underlineEl.attributes[.foregroundColor] as? NSColor, MarkdownTheme.shared.linkColor)
        XCTAssertNil(underlineEl.attributes[.font], "underline should inherit the heading font from the base element below it, not set its own")
        XCTAssertTrue(underlineEl.delimiterRanges.isEmpty)

        XCTAssertFalse(map.allDelimiterRanges.contains { text($0, in: source).contains("===") })
        XCTAssertFalse(map.allDelimiterRanges.contains { text($0, in: source).contains("body") })
    }

    /// Regression: CommonMark allows a Setext heading's content to span more
    /// than one physical line ("one or more lines of text" before the
    /// underline) — e.g. no blank line between a preceding paragraph and the
    /// heading merges that paragraph's last line(s) into the heading itself.
    /// MarkdownStyleMap used to assume content was always exactly the first
    /// line, which — given "# Heading\nTest\nHeading\n---\n" (no blank lines
    /// anywhere) — mistook the second content line ("Heading") for the
    /// underline itself (recoloring it and giving it the underline's
    /// spacing) while the real underline ("---") fell outside the element
    /// range entirely and rendered with no heading styling at all.
    func testSetextHeadingContentCanSpanMultipleLines() {
        let source = "# Heading\nTest\nHeading\n---\n"
        let map = MarkdownStyleMap(text: source)
        let nsSource = source as NSString

        XCTAssertEqual(map.headings.count, 2)
        XCTAssertEqual(map.headings[0].title, "Heading")
        XCTAssertEqual(map.headings[1].level, 2)
        // cmark folds the multi-line content into one space-joined title —
        // confirms this really is "Test" + "Heading" as one heading's text.
        XCTAssertEqual(map.headings[1].title, "Test Heading")

        // Elements overlap by design (a wide base element plus narrower
        // overlays for the continuation line and the underline — see
        // visitHeading), so "effective" attributes at a position are
        // whichever matching element sorts last, mirroring real application
        // order in MarkdownTextStorage.applyMarkdownStyling.
        func effectiveAttributes(at substring: String) -> [NSAttributedString.Key: Any]? {
            let range = nsSource.range(of: substring)
            guard range.location != NSNotFound else { return nil }
            return map.elements.filter { NSLocationInRange(range.location, $0.fullRange) }.last?.attributes
        }

        // "Test" (first content line) must carry the heading's big/bold font
        // and its actual color — it's heading content, not plain body text.
        let testAttrs = effectiveAttributes(at: "Test")
        XCTAssertEqual(testAttrs?[.foregroundColor] as? NSColor, MarkdownTheme.shared.headingColor)
        XCTAssertEqual((testAttrs?[.font] as? NSFont)?.pointSize, MarkdownTheme.shared.headingFonts[1].pointSize)
        XCTAssertEqual((testAttrs?[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacing, 0)

        // "Heading" (second content line, the continuation) must be the same
        // heading color — NOT the accent color, which the pre-fix bug gave
        // it by mistaking it for the underline — and must not repeat the
        // gap-above-heading spacing that "Test" already carries.
        let secondHeadingLineLocation = nsSource.range(of: "Heading", options: .backwards, range: NSRange(location: 0, length: nsSource.range(of: "---").location)).location
        let continuationAttrs = map.elements.filter { NSLocationInRange(secondHeadingLineLocation, $0.fullRange) }.last?.attributes
        XCTAssertEqual(continuationAttrs?[.foregroundColor] as? NSColor, MarkdownTheme.shared.headingColor)
        let continuationPara = continuationAttrs?[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(continuationPara?.paragraphSpacingBefore, 0, "second content line must not repeat the gap-above-heading spacing")
        XCTAssertEqual(continuationPara?.paragraphSpacing, 0)

        // The real underline is the *third* line down ("---"), not "Heading".
        let underlineAttrs = effectiveAttributes(at: "---")
        XCTAssertEqual(underlineAttrs?[.foregroundColor] as? NSColor, MarkdownTheme.shared.linkColor)
        XCTAssertEqual((underlineAttrs?[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacingBefore, 0)
        XCTAssertGreaterThan((underlineAttrs?[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacing ?? 0, 0,
                             "gap after the whole heading block, before whatever follows, must be preserved")
    }

    // MARK: - Thematic breaks

    /// A thematic break ("---"/"***"/"___") is the purest case of "the whole
    /// line is the delimiter" — same accent-color treatment as a blockquote's
    /// ">" or a table's pipes, rather than being left in the default color.
    func testThematicBreakIsAccentColored() {
        let source = "above\n\n***\n\nbelow\n"
        let map = MarkdownStyleMap(text: source)
        guard let breakEl = map.elements.first(where: {
            text($0.fullRange, in: source).trimmingCharacters(in: .whitespacesAndNewlines) == "***"
        }) else {
            return XCTFail("no thematic break element found")
        }
        XCTAssertEqual(breakEl.attributes[.foregroundColor] as? NSColor, MarkdownTheme.shared.linkColor)
        XCTAssertTrue(breakEl.delimiterRanges.isEmpty, "the rule must stay visible, not be hidden as a delimiter")
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

    // MARK: - List bullet markers

    /// Bullet markers render the literal source character ("-"/"*"/"+"),
    /// just recolored — not a depth-cycling substitute shape (●/○/♦/♢), the
    /// prior behavior. The marker character is real source content (a
    /// CommonMark list splits into a new list when the marker changes), so
    /// three sibling-nested lists using three different markers should each
    /// keep showing their own marker, distinguished only by accent color and
    /// indentation — not collapsed into a single app-invented shape sequence.
    func testUnorderedBulletMarkersStayLiteralAndAccentColored() {
        let source = "- top\n  * nested\n    + deeper\n"
        let map = MarkdownStyleMap(text: source)
        let markerChars = ["-", "*", "+"]
        let bulletElements = map.elements.filter {
            $0.fullRange.length == 1 && markerChars.contains(text($0.fullRange, in: source))
        }
        XCTAssertEqual(bulletElements.count, 3)
        for (element, expectedMarker) in zip(bulletElements, markerChars) {
            XCTAssertEqual(text(element.fullRange, in: source), expectedMarker)
            XCTAssertEqual(element.attributes[.foregroundColor] as? NSColor, MarkdownTheme.shared.linkColor)
            XCTAssertNil(element.attributes[.font], "bullet marker should inherit the body font, not a dedicated bullet font")
            XCTAssertTrue(element.delimiterRanges.isEmpty, "the marker must stay visible, not be hidden as a delimiter")
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

        let bulletElements = map.elements.filter { text($0.fullRange, in: source) == "-" }
        XCTAssertEqual(bulletElements.count, 1)
    }

    // MARK: - List continuation indent (hanging indent for wrapped lines)

    private func headIndent(in map: MarkdownStyleMap) -> CGFloat? {
        for element in map.elements {
            if let para = element.attributes[.paragraphStyle] as? NSParagraphStyle, para.headIndent > 0 {
                return para.headIndent
            }
        }
        return nil
    }

    /// A wrapped continuation line-fragment (window too narrow for the whole
    /// item) should line up under the first line's text, not fall back to
    /// the paragraph's left margin — this is what headIndent controls.
    /// firstLineHeadIndent must stay 0 since the first line's own indent
    /// already comes from real marker/space characters in the source.
    ///
    /// Source text must run at least 60 characters (see
    /// `testHangingIndentSkippedForShortLinesRegardlessOfNesting` below for
    /// why) purely to satisfy that gate — it isn't what this test is about.
    func testTopLevelBulletItemGetsPositiveHeadIndentWithZeroFirstLineIndent() {
        let source = "- Some list item text long enough to plausibly wrap in a window\n"
        let map = MarkdownStyleMap(text: source)
        guard let element = map.elements.first(where: {
            ($0.attributes[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? 0 > 0
        }) else {
            return XCTFail("no list-item paragraph-style element found")
        }
        let para = element.attributes[.paragraphStyle] as! NSParagraphStyle
        XCTAssertGreaterThan(para.headIndent, 0)
        XCTAssertEqual(para.firstLineHeadIndent, 0)
        // Covers the whole physical line, not just the "- " prefix, since
        // NSParagraphStyle's headIndent/firstLineHeadIndent are read per
        // paragraph (line), not per sub-range.
        XCTAssertEqual(text(element.fullRange, in: source), "- Some list item text long enough to plausibly wrap in a window")
    }

    /// A nested item's indent must be measurably larger than its parent's —
    /// otherwise a wrapped nested line would visually align with the parent
    /// list's text instead of its own.
    func testNestedListItemHasLargerHeadIndentThanTopLevel() {
        let topSource = "- top level item with enough text to clear the wrap-plausibility gate\n"
        let nestedSource = "- top level item with enough text to clear the wrap-plausibility gate\n  - nested item that also clears the same length gate on its own\n"
        let topIndent = headIndent(in: MarkdownStyleMap(text: topSource))
        let nestedMap = MarkdownStyleMap(text: nestedSource)
        // The nested item's own indent is the larger of the two headIndent
        // values present (the top-level line also has one).
        let allIndents = nestedMap.elements.compactMap { ($0.attributes[.paragraphStyle] as? NSParagraphStyle)?.headIndent }.filter { $0 > 0 }
        guard let topIndent, let maxNestedIndent = allIndents.max() else {
            return XCTFail("expected headIndent values for both items")
        }
        XCTAssertGreaterThan(maxNestedIndent, topIndent)
    }

    /// A wider ordered-list marker ("10." vs "1.") must produce a wider
    /// measured indent — the indent is based on rendered prefix width, not
    /// a fixed guess, so it should track the marker's actual character count.
    func testOrderedListWiderMarkerProducesLargerHeadIndent() {
        let narrowIndent = headIndent(in: MarkdownStyleMap(text: "1. an item with enough trailing text to clear the length gate\n"))
        let wideIndent = headIndent(in: MarkdownStyleMap(text: "10. an item with enough trailing text to clear the length gate\n"))
        guard let narrowIndent, let wideIndent else {
            return XCTFail("expected headIndent values for both ordered items")
        }
        XCTAssertGreaterThan(wideIndent, narrowIndent)
    }

    /// A checkbox item's own bullet/number marker is hidden entirely (see
    /// the checkbox glyph-hiding element above), so the continuation indent
    /// must still come out positive from just the leading indentation plus
    /// the visible "[ ]" bracket — not silently skipped because the marker
    /// itself contributes no width.
    func testCheckboxListItemGetsPositiveHeadIndent() {
        let source = "- [ ] Some task with enough trailing text to clear the length gate\n"
        let indent = headIndent(in: MarkdownStyleMap(text: source))
        XCTAssertNotNil(indent)
        XCTAssertGreaterThan(indent ?? 0, 0)
    }

    /// Regression: applying a nonzero `NSParagraphStyle.headIndent` to a list
    /// item's line — even with firstLineHeadIndent correctly left at 0 —
    /// was found (empirically, in the real app, not explained by anything in
    /// this file) to visibly shift that line's *first* rendering rightward
    /// by exactly the headIndent amount, for any paragraph other than the
    /// very first one in the whole document. Concretely: pasting a plain
    /// two-item checklist ("- [ ] A\n- [ ] B\n") rendered item A's checkbox
    /// flush left as expected, but item B's checkbox 59px further right —
    /// misaligning every list item after the first one in any list, task or
    /// not. Since hanging indent only ever matters for a line that actually
    /// wraps, and most list items (checklists especially) don't, short lines
    /// must not get a headIndent element created for them at all.
    func testHangingIndentSkippedForShortLinesRegardlessOfNesting() {
        let source = "- [ ] A\n- [ ] B\n"
        let map = MarkdownStyleMap(text: source)
        XCTAssertNil(headIndent(in: map), "a short list item's line should not get a hanging-indent paragraph style at all")
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

    /// CommonMark only lets a list marker interrupt an in-progress paragraph
    /// when it's indented 0–3 spaces past the parent item's own content
    /// column — indent it further (here, 8 spaces under a 2-space-wide "* "
    /// marker, 6 past the threshold) and it's swallowed as plain lazy-
    /// continuation text of the *previous* line's paragraph instead of
    /// starting a nested list. This isn't specific to this app (any
    /// CommonMark-compliant renderer does the same); it exists so a future
    /// change doesn't "fix" the missing color/indent by trying to make
    /// over-indented lines act like list items, which would diverge from
    /// the spec.
    func testOverIndentedBulletIsNotParsedAsNestedListItem() {
        let source = "* Parent item text\n        * Eight spaces in — too far to interrupt the paragraph\n"
        let map = MarkdownStyleMap(text: source)
        let bulletMarkers = map.elements.filter { text($0.fullRange, in: source) == "*" }
        XCTAssertEqual(bulletMarkers.count, 1, "only the parent's own marker should be recognized as a list-bullet element")
    }

    /// Regression: checking a task item whose text is followed by a nested
    /// sub-list used to grey out (via `checkedTaskTextAttributes`) not just
    /// the task's own text but the *entire nested sub-list's* text too —
    /// because `listItem.range` (used to bound the dimming range) spans a
    /// checkbox item's nested children as well as its own paragraph, in
    /// cmark-swift/swift-markdown's block structure. Only the task's own
    /// first child (its own paragraph, "Location acceptable?") should dim;
    /// the nested items are a separate, unrelated list and shouldn't visibly
    /// react to their parent's checked state at all.
    func testCheckedTaskDimmingDoesNotBleedIntoNestedSublist() {
        let source = "- [x] Location acceptable?\n  - Fully remote\n  - Second\n"
        let map = MarkdownStyleMap(text: source)
        let ownTextRange = (source as NSString).range(of: "Location acceptable?")
        let nestedRange = (source as NSString).range(of: "Fully remote")

        let dimmed = map.elements.filter { $0.attributes[.foregroundColor] != nil && $0.attributes[.font] == nil }
        XCTAssertTrue(
            dimmed.contains { NSEqualRanges($0.fullRange, NSRange(location: ownTextRange.location, length: NSMaxRange(ownTextRange) - ownTextRange.location)) || $0.fullRange.contains(ownTextRange.location) },
            "the task's own text should still be dimmed when checked"
        )
        XCTAssertFalse(
            dimmed.contains { NSIntersectionRange($0.fullRange, nestedRange).length > 0 },
            "a checked parent task must not dim its nested sub-list's text"
        )
    }
}
