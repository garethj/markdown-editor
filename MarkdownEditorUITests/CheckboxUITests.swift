import XCTest

/// Regression coverage for real mouse hit-testing on task-list checkboxes
/// (`EditorTextView.mouseDown` → `characterIndex(at:)` → click handler). The
/// unit suite only calls the click handler directly with a known character
/// index — it never goes through an actual click at a screen point.
final class CheckboxUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        UITestSupport.launchWithFreshDocument(app)
    }

    override func tearDownWithError() throws {
        UITestSupport.terminateCleanly(app)
    }

    func testCheckboxClickTogglesTaskState() throws {
        let textView = app.textViews["MarkdownEditorTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        textView.click()
        textView.typeText("- [ ] task one")

        // The "- " marker renders zero-width (hidden delimiter), so the
        // checkbox bracket is the first visible content on the line, right at
        // the text container's left inset (40pt) and vertically centered on
        // the first line (20pt top inset + roughly half a ~22pt line height).
        let checkboxPoint = textView.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 52, dy: 31))
        checkboxPoint.click()

        let valueAfterFirstClick = textView.value as? String ?? ""
        XCTAssertTrue(valueAfterFirstClick.contains("[x]"), "expected click to check the box, got: \(valueAfterFirstClick)")

        checkboxPoint.click()
        let valueAfterSecondClick = textView.value as? String ?? ""
        XCTAssertTrue(valueAfterSecondClick.contains("[ ]"), "expected second click to uncheck the box, got: \(valueAfterSecondClick)")
    }

    /// Regression: `NSParagraphStyle.headIndent` (added for hanging-indent on
    /// wrapped list-item continuation lines) was found to visibly shift the
    /// *first* line of every list item after the first one in the whole
    /// document rightward by its own headIndent value — even with
    /// firstLineHeadIndent correctly left at 0 (see
    /// MarkdownStyleMapTests.testHangingIndentSkippedForShortLinesRegardlessOfNesting
    /// for the headless half of this fix). Both "A" and "B" here are
    /// top-level, unindented checkbox items, so their checkboxes must land
    /// at the exact same x-offset from the text container's left edge —
    /// clicking item B's checkbox at the identical offset that checks item
    /// A's confirms they're still aligned, the same way
    /// testCheckboxClickTogglesTaskState confirms item A's own position.
    func testConsecutiveTopLevelCheckboxesAlignAtSameXOffset() throws {
        let textView = app.textViews["MarkdownEditorTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        UITestSupport.pasteText("- [ ] A\n- [ ] B\n", into: textView, app: app)

        let firstLineCheckboxPoint = textView.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 52, dy: 31))
        firstLineCheckboxPoint.click()
        XCTAssertTrue(
            (textView.value as? String ?? "").contains("- [x] A"),
            "expected the click at item A's known checkbox offset to check it"
        )

        let secondLineCheckboxPoint = textView.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 52, dy: 31 + 22))
        secondLineCheckboxPoint.click()
        XCTAssertTrue(
            (textView.value as? String ?? "").contains("- [x] B"),
            "expected the click one line down, at the *same* x-offset, to check item B — " +
            "if this fails, item B's checkbox rendered at a different x-offset than item A's"
        )
    }

    /// Regression: clicking a checkbox while the selection/cursor was left
    /// somewhere far away (e.g. at the end of a long document, from before
    /// the click — never having clicked on the checkbox's own line first)
    /// scrolled the whole view to wherever that stale selection was, not to
    /// the checkbox just clicked. Root cause: `handleCheckboxClick` called
    /// `textView.insertText(_:replacementRange:)` without first moving the
    /// selection to the checkbox — `insertText(_:replacementRange:)` doesn't
    /// reliably relocate the selection to an edit made away from wherever it
    /// already was, so `textDidChange`'s `updateCursorReveal()` (which fires
    /// synchronously from inside that same `insertText` call) read the
    /// *stale* `selectedRange()`, invalidated glyphs/layout way over there,
    /// and AppKit auto-scrolled to keep that stale selection visible.
    /// Reproduced with a real, much longer document
    /// (job-hunt-reference.md-shaped: a checkbox a few lines down, ~60
    /// lines of filler after it) — a short in-memory doc doesn't leave the
    /// cursor far enough away after paste to trigger it.
    func testCheckboxClickDoesNotScrollToStaleCursorPosition() throws {
        let textView = app.textViews["MarkdownEditorTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 10))

        let tailFiller = (1...60).map { "Line \($0) of filler text to make the document scrollable." }.joined(separator: "\n")
        let doc = "Filler line before the checklist.\n- [ ] Task to check\n\n\(tailFiller)\n"
        UITestSupport.pasteText(doc, into: textView, app: app)
        // Cursor lands at the very end of the document (bottom of the tail
        // filler) after paste, which also scrolls the view down there.
        // Scroll back up to see the checkbox WITHOUT clicking or otherwise
        // moving the cursor away from the end — the cursor staying far away
        // is the reported repro condition, not merely "cursor not exactly on
        // the checkbox's line."
        for _ in 0..<40 {
            textView.scroll(byDeltaX: 0, deltaY: 15)
        }
        Thread.sleep(forTimeInterval: 0.3)

        let sampleRect = CGRect(x: 0, y: 150, width: 500, height: 150)
        let before = textView.screenshot()

        let checkboxPoint = textView.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 52, dy: 31 + 22))
        checkboxPoint.click()
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertTrue(
            (textView.value as? String ?? "").contains("[x] Task to check"),
            "expected the click to check the box"
        )

        let after = textView.screenshot()
        let diff = PixelSample.regionDifference(before, after, rect: sampleRect)
        XCTAssertLessThan(diff, 0.05, "the view scrolled away from the checkbox — it should stay in place")
    }
}
