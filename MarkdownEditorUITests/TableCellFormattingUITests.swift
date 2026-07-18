import XCTest

/// Regression coverage for cursor-reveal of nested inline formatting (bold,
/// italic) inside table cells. `MarkdownStyleMapTests` covers the underlying
/// invariant directly (elements sorted by location), but whether the cursor
/// actually reaching a character position inside the table causes the real
/// `NSLayoutManager` to reveal the delimiter glyphs on screen is only
/// observable through a real window laying real glyphs — the unit suite
/// can't reach `MarkdownTextView.Coordinator.updateCursorReveal` at all.
final class TableCellFormattingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        UITestSupport.launchWithFreshDocument(app)
    }

    override func tearDownWithError() throws {
        UITestSupport.terminateCleanly(app)
    }

    func testBoldDelimitersRevealWhenCursorEntersTableCell() throws {
        let textView = app.textViews["MarkdownEditorTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        textView.click()

        // Three lines: header, separator, and a data row whose second cell is
        // bold. Cursor ends at the absolute end (after the final "|"), well
        // outside the bold span, once typing finishes.
        UITestSupport.pasteText("| A | B |\n| --- | --- |\n| x | **Lead** |", into: textView, app: app)
        Thread.sleep(forTimeInterval: 0.5) // let the initial full parse/layout settle

        // PixelSample.regionDifference's rect is in the screenshot's own pixel
        // space (retina-scaled), not points, and clamps to the image's actual
        // bounds — so an intentionally oversized rect safely covers this
        // whole (very short, 3-line) document without needing to compute
        // row 3's exact pixel offset.
        let contentRect = CGRect(x: 0, y: 0, width: 4000, height: 4000)
        let beforeEntering = textView.screenshot()

        // Move the cursor from the end of the typed text to land inside
        // "Lead" (between "Le" and "ad") using only relative key presses —
        // no absolute screen-point math, so this doesn't depend on font
        // metrics or kerning to hit the right character.
        for _ in 0..<6 {
            textView.typeKey(.leftArrow, modifierFlags: [])
        }
        Thread.sleep(forTimeInterval: 0.5) // let updateCursorReveal's glyph invalidation redraw

        let afterEntering = textView.screenshot()
        // Diluted by averaging over the whole (mostly blank) 3-line document
        // rather than just the affected row, so the real signal is much
        // smaller than LayoutUITests' single-line-strip threshold — measured
        // ~0.008 for a genuine reveal vs exactly 0.0 for none at all.
        let diff = PixelSample.regionDifference(beforeEntering, afterEntering, rect: contentRect)
        XCTAssertGreaterThan(diff, 0.001,
            "moving the cursor inside \"Lead\" should reveal its ** delimiters, changing the row's rendered pixels")
    }

    /// Regression: `applyMarkdownStyling` used to report the dirty-region
    /// widening step's full range (which, for an edit inside a table, is the
    /// *whole table*) via `self.edited(.editedAttributes, ...)` so the
    /// layout manager would redisplay it — but that's the same channel
    /// NSTextView listens on to move the selection after an edit, so it
    /// moved the cursor to the end of that range (i.e. past the whole
    /// table) on every keystroke typed inside one, regardless of where in
    /// the table you were actually typing.
    func testTypingInsideTableCellDoesNotMoveCursorPastTable() throws {
        let textView = app.textViews["MarkdownEditorTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        textView.click()

        UITestSupport.pasteText("| A | B |\n| --- | --- |\n| x | y |\nafter", into: textView, app: app)
        Thread.sleep(forTimeInterval: 0.5)

        // Cursor is after "after"; move it back into the "y" cell, right
        // after "y" and before " |" — 2 left-arrows past "after\n" plus the
        // width of " |\n" gets there, but simplest and least fragile is to
        // count from the unique "y" landmark instead of hardcoding an
        // absolute offset.
        let fullTextBeforeEdit = textView.value as? String ?? ""
        guard let yRange = fullTextBeforeEdit.range(of: "| x | y |") else {
            return XCTFail("table row not found in typed text")
        }
        let charsAfterY = fullTextBeforeEdit.distance(from: yRange.upperBound, to: fullTextBeforeEdit.endIndex) + 2
        for _ in 0..<charsAfterY {
            textView.typeKey(.leftArrow, modifierFlags: [])
        }
        // Multiple keystrokes in sequence, not one — a jump after the first
        // keystroke's own processEditing/applyMarkdownStyling pass wouldn't
        // show up from a single character (the char lands correctly before
        // any jump can happen), but the *second* character would land
        // wherever the cursor jumped to after the first one's edit settled.
        textView.typeText("ZZZ")

        let result = textView.value as? String ?? ""
        XCTAssertTrue(result.contains("| x | yZZZ |"),
            "typing inside the \"y\" cell should insert there, not move the cursor past the table — got: \(result)")
        XCTAssertTrue(result.hasSuffix("after"),
            "some typed character landed after \"after\" instead of inside the table cell — got: \(result)")
    }
}
