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
}
