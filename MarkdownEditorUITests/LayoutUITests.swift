import XCTest

/// Covers the "does it actually render correctly on screen" gap the unit
/// suite structurally can't touch — this bug class ("scroll-to-bottom on
/// every keystroke") only manifests through a real NSLayoutManager laying
/// glyphs into a real, sized window. A window-resize-reflow test was
/// attempted here too, but synthesizing a reliable window-border drag proved
/// too unreliable across window states (esp. a zoomed/maximized window) to
/// keep — see CLAUDE.md's remaining-gaps list.
final class LayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        UITestSupport.launchWithFreshDocument(app)
    }

    override func tearDownWithError() throws {
        UITestSupport.terminateCleanly(app)
    }

    /// Regression for "Fix scroll-to-bottom on every keystroke": editing one
    /// line must not move content elsewhere in the viewport.
    func testScrollPositionStableWhileTypingNearTop() throws {
        let textView = app.textViews["MarkdownEditorTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        textView.click()

        // Enough lines to make the document taller than one screen. Pasted
        // rather than typed character-by-character — MarkdownTextStorage
        // re-parses the whole document on every keystroke (see CLAUDE.md),
        // so 50 lines' worth of synthesized keystrokes is O(n²) and slow.
        let lines = (1...50).map { "Line \($0) of the scroll-stability regression test." }.joined(separator: "\n")
        UITestSupport.pasteText(lines, into: textView, app: app)
        textView.typeKey(.upArrow, modifierFlags: .command) // moveToBeginningOfDocument:
        Thread.sleep(forTimeInterval: 0.5) // let layout/scroll settle before sampling

        // A strip a few lines below the very top — unaffected by editing
        // line 1 itself, but would change entirely if the view scrolled.
        let sampleRect = CGRect(x: 0, y: 100, width: 300, height: 60)
        let before = textView.screenshot()

        textView.typeText("X")
        Thread.sleep(forTimeInterval: 0.5)

        let after = textView.screenshot()
        let diff = PixelSample.regionDifference(before, after, rect: sampleRect)
        XCTAssertLessThan(diff, 0.05, "content below the edit moved — the view likely scrolled instead of staying put")
    }
}
