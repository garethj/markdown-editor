import XCTest
@testable import MarkdownEditor

final class MarkdownTextStorageTests: XCTestCase {

    private func makeStorage(_ text: String) -> MarkdownTextStorage {
        let storage = MarkdownTextStorage()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        return storage
    }

    private func attributes(at index: Int, in storage: MarkdownTextStorage) -> [NSAttributedString.Key: Any] {
        storage.attributes(at: index, effectiveRange: nil)
    }

    func testInitialFullParseAppliesBoldAttributes() {
        let source = "Hello **world**"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "world").location
        let font = attributes(at: idx, in: storage)[.font] as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    /// Regression coverage for `mergeFontTraits`: nesting bold inside italic
    /// (or vice versa) must produce a single merged bold-italic font, not
    /// just whichever formatting was applied last.
    /// Regression: the rounded system design used for bold body text (see
    /// MarkdownTheme.roundedFont) has no true italic face — merging bold
    /// (rounded) with italic used to silently drop the italic trait rather
    /// than falling back to a descriptor that actually has one.
    func testNestedBoldInsideItalicMergesToBoldItalicFont() {
        let source = "_text **bold** text_"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "bold").location
        let traits = (attributes(at: idx, in: storage)[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold))
        XCTAssertTrue(traits.contains(.italic))
    }

    func testNestedItalicInsideBoldMergesToBoldItalicFont() {
        let source = "**text _italic_ text**"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "italic").location
        let traits = (attributes(at: idx, in: storage)[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold))
        XCTAssertTrue(traits.contains(.italic))
    }

    func testTripleAsteriskEmphasisMergesToBoldItalicFont() {
        let source = "***bold italic***"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "bold").location
        let traits = (attributes(at: idx, in: storage)[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold))
        XCTAssertTrue(traits.contains(.italic))
    }

    func testFencedCodeBlockAppliesMonospaceFont() {
        let source = "```\nlet x = 1\n```\n"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "let x").location
        let traits = (attributes(at: idx, in: storage)[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.monoSpace))
    }

    /// Regression: a compound construct (blockquote) has one wide "whole
    /// block" element plus one small colored "> " marker element per line.
    /// Editing only line two must not cause line one's marker color to be
    /// dropped when the wide element's re-application wins the race over a
    /// too-narrow dirty region.
    func testEditingOneBlockquoteLineDoesNotLoseAnotherLinesMarkerColor() {
        let storage = makeStorage("> line one\n> line two\n")
        XCTAssertEqual(markerColor(in: storage, lineIndex: 0), MarkdownTheme.shared.linkColor)

        // Edit scoped to line two only: append a character at its end.
        let lineTwoEnd = (storage.string as NSString).length - 1 // before trailing "\n"
        storage.replaceCharacters(in: NSRange(location: lineTwoEnd, length: 0), with: "!")

        XCTAssertEqual(
            markerColor(in: storage, lineIndex: 0), MarkdownTheme.shared.linkColor,
            "line one's '>' marker color must survive an edit scoped to line two"
        )
    }

    /// Regression: deleting a Setext heading's "===" underline must revert the
    /// text line above it back to plain-paragraph styling, even though the
    /// edit itself only touches the underline's own line.
    func testDeletingSetextUnderlineRevertsHeadingLineToPlainFont() {
        let storage = makeStorage("Heading\n===\nbody\n")
        let headingFont = attributes(at: 0, in: storage)[.font] as? NSFont
        XCTAssertEqual(headingFont?.pointSize, MarkdownTheme.shared.headingFonts[0].pointSize)
        XCTAssertTrue(headingFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)

        let underlineRange = (storage.string as NSString).range(of: "===\n")
        XCTAssertNotEqual(underlineRange.location, NSNotFound)
        storage.replaceCharacters(in: underlineRange, with: "")

        let revertedFont = attributes(at: 0, in: storage)[.font] as? NSFont
        XCTAssertEqual(revertedFont?.pointSize, MarkdownTheme.shared.defaultFont.pointSize)
        XCTAssertFalse(revertedFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? true)
    }

    /// Regression: a Setext H1 underline is a run of literal "=" characters,
    /// which the "==(.+?)==" highlight pattern matches purely by
    /// coincidence — harmless while the underline was hidden (a highlight
    /// background behind zero-width glyphs is invisible), but once the
    /// underline became visible (recolored, not hidden), a false match
    /// painted stray yellow highlight blocks across it.
    func testSetextUnderlineIsNotFalselyHighlighted() {
        let storage = makeStorage("Heading\n========\nbody\n")
        let underlineStart = (storage.string as NSString).range(of: "========").location
        for offset in 0..<8 {
            XCTAssertNil(attributes(at: underlineStart + offset, in: storage)[.backgroundColor],
                         "underline character at offset \(offset) must not be highlighted")
        }
    }

    /// Companion to the above: real `==highlighted==` text outside a heading
    /// must still work — the exclusion is scoped to heading ranges, not a
    /// blanket disabling of the highlight feature.
    func testRealHighlightStillWorksOutsideHeadings() {
        let storage = makeStorage("a sentence with ==highlighted text== in it\n")
        let contentStart = (storage.string as NSString).range(of: "highlighted text").location
        XCTAssertNotNil(attributes(at: contentStart, in: storage)[.backgroundColor])
    }

    /// Regression: a Setext heading's text line and its own "==="/"---"
    /// underline are two separate NSTextView paragraphs even though they're
    /// one markdown node. Applying the heading's single before-and-after
    /// paragraph-spacing style to both used to double-count the gap between
    /// them (text line's own spacing-after + underline's own
    /// spacing-before), visibly separating "Heading" from its own "===".
    /// The content line should keep its spacing *before* (gap above the
    /// heading) but drop spacing *after*; the underline should do the
    /// reverse.
    func testSetextHeadingHasNoGapBetweenTextAndUnderline() {
        let storage = makeStorage("Heading\n===\nbody\n")
        let contentPara = attributes(at: 0, in: storage)[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(contentPara?.paragraphSpacing, 0, "no gap should open up below the heading text, before its own underline")
        XCTAssertGreaterThan(contentPara?.paragraphSpacingBefore ?? 0, 0, "gap above the heading block itself must be preserved")

        let underlineStart = (storage.string as NSString).range(of: "===").location
        let underlinePara = attributes(at: underlineStart, in: storage)[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(underlinePara?.paragraphSpacingBefore, 0, "no gap should open up above the underline, below the heading text")
        XCTAssertGreaterThan(underlinePara?.paragraphSpacing ?? 0, 0, "gap after the heading block, before what follows, must be preserved")
    }

    /// Regression: table column kerning is recomputed for the whole table on
    /// every keystroke (full AST reparse), and the dirty-region widening step
    /// already unions in the table's whole-table element — but the actual
    /// attribute writes go straight to `backingStore`, bypassing
    /// `self.setAttributes`, so nothing told the layout manager anything
    /// changed outside the literally-typed characters. That left other rows'
    /// kerning correctly recomputed in the attribute store but undisplayed
    /// until some unrelated event (e.g. the cursor leaving the table) forced
    /// a redraw there. `applyMarkdownStyling` must call
    /// `invalidateDisplay(forCharacterRange:)` for the full widened range so
    /// the layout manager redisplays every row whose kerning could have
    /// changed — not `self.edited(.editedAttributes, ...)`, which was tried
    /// first and reports through the same channel NSTextView listens on to
    /// move the selection after an edit, moving the cursor to the end of the
    /// widened range (i.e. past the whole table) on every keystroke inside
    /// one.
    final class RecordingLayoutManager: NSLayoutManager {
        var recordedRanges: [NSRange] = []
        var recordedLayoutInvalidations: [NSRange] = []
        override func invalidateDisplay(forCharacterRange charRange: NSRange) {
            recordedRanges.append(charRange)
            super.invalidateDisplay(forCharacterRange: charRange)
        }
        override func invalidateLayout(forCharacterRange charRange: NSRange, actualCharacterRange: NSRangePointer?) {
            recordedLayoutInvalidations.append(charRange)
            super.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: actualCharacterRange)
        }
    }

    func testEditingOneTableRowNotifiesLayoutManagerAboutOtherRowsKernRange() {
        let source = "| Name | Info |\n| --- | --- |\n| Alice | Hi |\n| Bo | Hi |\n"
        let storage = MarkdownTextStorage()
        let lm = RecordingLayoutManager()
        storage.addLayoutManager(lm)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        lm.recordedRanges.removeAll()

        // Widen "Bo" to "Bobbington" — column 0's max width grows past
        // "Alice" (5 chars), which means "Alice"'s own kern must increase to
        // keep the column aligned, even though the edit itself is scoped to
        // a different, later line.
        let boRange = (storage.string as NSString).range(of: "Bo |")
        storage.replaceCharacters(in: NSRange(location: boRange.location + 2, length: 0), with: "bbington")

        let aliceIdx = (storage.string as NSString).range(of: "Alice").location
        let notifiedAboutAlice = lm.recordedRanges.contains { NSLocationInRange(aliceIdx, $0) }
        XCTAssertTrue(notifiedAboutAlice,
                      "layout manager must be notified about other rows whose kerning changed")
    }

    /// Regression: typing "Heading" then "\n===" finishes a Setext heading,
    /// which grows the font on the *"Heading" line* — a line the literal
    /// edit (typing "===" on the line below it) never directly touches, so
    /// NSLayoutManager's cached line-fragment geometry for it stays sized
    /// for the old, smaller font unless something explicitly tells the
    /// layout manager to recompute. All the attribute writes in
    /// applyMarkdownStyling go straight to backingStore (bypassing
    /// self.setAttributes), so nothing tells it via the normal edited()
    /// channel either — invalidateDisplay(forCharacterRange:) alone only
    /// requests a *redraw*, not a *re-layout*, so it'd mark the old
    /// (still-cached, still-short) rect dirty and the taller glyph's top
    /// gets clipped by that stale region on screen. invalidateLayout must
    /// run first so the geometry is fresh by the time invalidateDisplay
    /// computes what to redraw.
    func testFinishingSetextHeadingInvalidatesLayoutForTextLineAbove() {
        let storage = MarkdownTextStorage()
        let lm = RecordingLayoutManager()
        storage.addLayoutManager(lm)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Heading")
        lm.recordedLayoutInvalidations.removeAll()

        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "\n===")

        let headingLineStart = 0 // "Heading" is the very first character
        let layoutInvalidatedForHeadingLine = lm.recordedLayoutInvalidations.contains {
            NSLocationInRange(headingLineStart, $0)
        }
        XCTAssertTrue(layoutInvalidatedForHeadingLine,
                      "layout manager must recompute geometry for the heading text line, not just redraw it")
    }

    /// Regression: two backspaces in a row at the end of any multi-line
    /// document used to crash — the first deletes the trailing newline, the
    /// second deletes the character before it. Nothing markdown-specific
    /// about the trigger (this reproduces with plain, construct-free text);
    /// it was first reported as "crashes when backspacing in a bullet," but
    /// that was incidental to what the user happened to be editing, not the
    /// cause. Needs the real NSTextView.deleteBackward: path (not just
    /// storage.replaceCharacters) plus a real NSLayoutManager + NSTextContainer,
    /// since the crash lived inside NSLayoutManager's private rect
    /// computation, not in MarkdownTextStorage's own range math.
    ///
    /// Root cause: MarkdownTextStorage.processEditing() called
    /// applyMarkdownStyling() — which ends by calling
    /// NSLayoutManager.invalidateDisplay(forCharacterRange:) — *before*
    /// calling super.processEditing(). super.processEditing() is what
    /// actually notifies attached layout managers of the edit's
    /// character-count change; calling invalidateDisplay before that let
    /// NSLayoutManager compute rects while its internal glyph cache still
    /// reflected the pre-edit (longer) text length, reading past the
    /// already-shortened backingStore string on the very next edit. Fixed by
    /// deferring the invalidateDisplay call to run after super.processEditing().
    func testConsecutiveBackspacesAtDocumentEndDoNotCrash() {
        let storage = MarkdownTextStorage()
        let lm = NSLayoutManager()
        let delegate = MarkdownLayoutManagerDelegate()
        lm.delegate = delegate
        storage.addLayoutManager(lm)
        let container = MarkdownTextContainer()
        container.proseWidth = 600
        lm.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "hello\nworld\n")
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))
        while storage.length > 0 {
            textView.deleteBackward(nil)
        }
        XCTAssertEqual(storage.string, "")
    }

    /// Regression: selecting all text (including a table) and deleting it in
    /// one edit used to crash — but only later, when something completely
    /// unrelated to the edit (an animated window-zoom resize, triggered by
    /// double-clicking the title bar) forced a redraw. Confirmed via a real
    /// crash report: NSMoveHelper's animation timer fired a redraw whose
    /// call stack traces straight into MarkdownTextStorage.attributes(at:)
    /// with an out-of-bounds index — nothing in that stack belongs to our
    /// own edit/invalidation code.
    ///
    /// applyMarkdownStyling()'s empty-document early-return path skipped two
    /// things every other edit does: (1) it left
    /// MarkdownTextContainer.tableLineRanges pointing at character ranges
    /// from whatever document existed a moment ago — lineFragmentRect(forProposedRect:at:...)
    /// binary-searches that array on every layout pass, including ones
    /// triggered by something that has nothing to do with us; (2) it never
    /// set pendingDisplayInvalidationRange, so none of the extra
    /// invalidateLayout/invalidateDisplay cleanup that runs after every
    /// other edit ran for this one either — the transition to empty relied
    /// entirely on the standard edited()-driven notification, which this
    /// crash shows isn't sufficient once an unrelated animation is racing
    /// against it in the real (asynchronous, CVDisplayLink-driven) app.
    func testSelectAllDeleteThenSimulatedWindowResizeDoesNotCrash() {
        let storage = MarkdownTextStorage()
        let lm = NSLayoutManager()
        let delegate = MarkdownLayoutManagerDelegate()
        lm.delegate = delegate
        storage.addLayoutManager(lm)
        let container = MarkdownTextContainer()
        container.proseWidth = 600
        lm.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Heading\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n")
        XCTAssertEqual(container.tableLineRanges.count, 1)

        textView.setSelectedRange(NSRange(location: 0, length: storage.length))
        textView.deleteBackward(nil)
        XCTAssertEqual(storage.length, 0)
        XCTAssertEqual(container.tableLineRanges.count, 0, "stale table ranges must not survive the document becoming empty")

        // Simulate the animated resize itself — each width change fires
        // MarkdownTextContainer.proseWidth's didSet, then force a redraw the
        // same way the real crash's display-link callback did.
        for width in stride(from: 600, through: 900, by: 50) {
            container.proseWidth = CGFloat(width)
            textView.display()
        }
    }

    /// Companion to the above, at the narrowest possible scope: even without
    /// reproducing the animation timing, MarkdownTextStorage's own override
    /// must never let an out-of-bounds attributes(at:) query crash the app —
    /// AppKit's TextKit internals are the caller here, not our code, and the
    /// crash above proves they can race ahead of our invalidation under real
    /// conditions a synchronous unit test can't fully replicate.
    func testAttributesAtOutOfBoundsLocationDoesNotCrash() {
        let storage = makeStorage("hello")
        XCTAssertTrue(attributes(at: 100, in: storage).isEmpty)
        XCTAssertTrue(attributes(at: -1, in: storage).isEmpty)
        XCTAssertTrue(attributes(at: storage.length, in: storage).isEmpty,
                      "location == length is one past the last valid index")
    }

    // MARK: - Emoji font override

    /// Regression: emoji characters (✅❌🟡 etc.) had no explicit font
    /// attribute of their own — like all plain text, they inherited the one
    /// shared rounded system font, leaving color-emoji glyph resolution
    /// entirely to AppKit's own font-cascade substitution at
    /// glyph-generation time. That substitution was found (via
    /// shouldGenerateGlyphs debug logging) to behave correctly on the
    /// initial full-document layout but corrupt the glyph into an unrelated
    /// character, or blank it, on an *incremental* relayout pass — e.g. one
    /// triggered by clicking a checkbox on another line. Stamping an
    /// explicit "Apple Color Emoji" font onto emoji grapheme clusters means
    /// the correct font is decided up front, not discovered via a fallback
    /// substitution that only works reliably on a full layout pass.
    func testEmojiCharacterGetsExplicitColorEmojiFont() {
        let source = "Status: \u{274C} done"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "\u{274C}").location
        let font = attributes(at: idx, in: storage)[.font] as? NSFont
        XCTAssertEqual(font?.fontName, "AppleColorEmoji")
    }

    /// A grapheme cluster that only renders as emoji via an explicit VS16
    /// (U+FE0F) selector — not every emoji has Emoji_Presentation=Yes by
    /// default — must still get the color font.
    func testEmojiWithVariationSelectorGetsExplicitColorEmojiFont() {
        let source = "Rating: \u{2764}\u{FE0F} good"
        let storage = makeStorage(source)
        // .literal: the default (grapheme-cluster-aware) search never
        // matches a bare scalar that's only part of a larger cluster —
        // the heart alone is mid-cluster once followed by VS16.
        let idx = (source as NSString).range(of: "\u{2764}", options: .literal).location
        let font = attributes(at: idx, in: storage)[.font] as? NSFont
        XCTAssertEqual(font?.fontName, "AppleColorEmoji")
    }

    /// Regression matching the exact real-world repro: clicking a checkbox
    /// to check it turned an unrelated emoji bullet a couple of lines below
    /// it into a garbled glyph. The checkbox edit only touches its own line
    /// directly, but a parent list item's own styled range spans its nested
    /// children (see the nested-dimming-bleed fix in MarkdownStyleMapTests),
    /// so effectiveDirtyRange widens to cover the whole nested sublist and
    /// triggers an *incremental* (not full) restyle of the emoji lines too
    /// — precisely the relayout path found to corrupt emoji glyphs. Confirms
    /// the emoji's explicit font attribute survives an edit elsewhere in the
    /// document, not just the initial full parse.
    func testEmojiFontOverrideSurvivesCheckboxToggleOnAnotherLine() {
        let source = "- [ ] Parent task\n  - \u{2705} Sub item one\n  - \u{274C} Sub item two\n"
        let storage = makeStorage(source)
        let nsSource = source as NSString
        let checkboxRange = nsSource.range(of: "[ ]")
        let firstEmojiIdx = nsSource.range(of: "\u{2705}").location
        let secondEmojiIdx = nsSource.range(of: "\u{274C}").location

        // Simulate clicking the checkbox: replace "[ ]" with "[x]", an edit
        // scoped to a different line than either emoji.
        storage.replaceCharacters(in: checkboxRange, with: "[x]")

        let firstFont = attributes(at: firstEmojiIdx, in: storage)[.font] as? NSFont
        let secondFont = attributes(at: secondEmojiIdx, in: storage)[.font] as? NSFont
        XCTAssertEqual(firstFont?.fontName, "AppleColorEmoji",
                       "emoji font override should survive an incremental edit on another line (first)")
        XCTAssertEqual(secondFont?.fontName, "AppleColorEmoji",
                       "emoji font override should survive an incremental edit on another line (second)")
    }

    private func markerColor(in storage: MarkdownTextStorage, lineIndex: Int) -> NSColor? {
        let lines = storage.string.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return nil }
        var offset = 0
        for i in 0..<lineIndex {
            offset += (lines[i] as NSString).length + 1
        }
        let nsText = storage.string as NSString
        guard offset < nsText.length, nsText.character(at: offset) == UInt16(UnicodeScalar(">").value) else {
            return nil
        }
        return attributes(at: offset, in: storage)[.foregroundColor] as? NSColor
    }
}
