import XCTest

/// Regression coverage for the real FileWatcher → merge/conflict path,
/// including real `DispatchSource` event timing and a real `NSAlert` sheet —
/// none of which `ExternalChangeResolverTests` (unit-level, contrived
/// inputs) or the deeper AppKit document-conflict tracking can exercise
/// without an actual saved file and an actual external process touching it.
final class ExternalChangeUITests: XCTestCase {
    private var app: XCUIApplication!
    private var scratchDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        scratchDir = UITestSupport.makeScratchDirectory()
        UITestSupport.launchWithFreshDocument(app)
    }

    override func tearDownWithError() throws {
        UITestSupport.terminateCleanly(app)
        try? FileManager.default.removeItem(at: scratchDir)
    }

    func testExternalEditSilentlyMergesWithNoLocalChanges() throws {
        let fileURL = scratchDir.appendingPathComponent("silent-merge.md")
        let textView = app.textViews["MarkdownEditorTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        textView.click()
        textView.typeText("Original content")

        textView.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(SavePanelAutomation.save(app: app, to: fileURL), "save panel did not complete")

        // No local changes since the save — an external edit should merge
        // silently, with no dialog of any kind.
        try "Externally edited content".write(to: fileURL, atomically: true, encoding: .utf8)

        let mergedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS 'Externally edited content'"),
            object: textView
        )
        let result = XCTWaiter().wait(for: [mergedExpectation], timeout: 10)
        XCTAssertEqual(result, .completed, "external edit was not silently merged into the editor")
        XCTAssertFalse(app.sheets.firstMatch.exists, "no dialog should appear for a silent merge")

        // applyExternalText clears the undo stack — Cmd+Z right after a
        // silent merge must be a no-op, not revert the merge.
        textView.typeKey("z", modifierFlags: .command)
        let valueAfterUndo = textView.value as? String ?? ""
        XCTAssertTrue(valueAfterUndo.contains("Externally edited content"), "undo should not revert a silent external merge")
    }

    func testExternalEditShowsConflictDialogAndKeepMinePreservesLocalText() throws {
        let fileURL = scratchDir.appendingPathComponent("conflict.md")
        let textView = app.textViews["MarkdownEditorTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        textView.click()
        textView.typeText("Original content")

        textView.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(SavePanelAutomation.save(app: app, to: fileURL), "save panel did not complete")

        // Unsaved local edit since the save.
        textView.typeText(" plus a local edit")

        try "Externally edited content".write(to: fileURL, atomically: true, encoding: .utf8)

        let alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "conflict dialog did not appear despite unsaved local changes")

        let keepMineButton = alert.buttons["Keep Mine"]
        XCTAssertTrue(keepMineButton.waitForExistence(timeout: 5))
        keepMineButton.click()
        UITestSupport.waitUntilGone(alert, timeout: 5)

        let value = textView.value as? String ?? ""
        XCTAssertTrue(value.contains("plus a local edit"), "Keep Mine should preserve the local edit, got: \(value)")
        XCTAssertFalse(value.contains("Externally edited content"), "Keep Mine should discard the external version")
    }
}
