import XCTest

/// Regression coverage for the WKWebView → NSPrintOperation pipeline, which
/// has a documented deadlock trap (`op.run()` blocks the main thread and
/// starves WebKit — `runModal` is required) and zero coverage in the unit
/// suite. If the deadlock regressed, the save panel would simply never
/// appear and this test would time out rather than fail fast.
final class PDFExportUITests: XCTestCase {
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

    func testPDFExportProducesFileWithoutHanging() throws {
        let pdfURL = scratchDir.appendingPathComponent("export-test.pdf")
        let textView = app.textViews["MarkdownEditorTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        textView.click()
        textView.typeText("# Test Document\n\nSome body text for the PDF export smoke test.")

        textView.typeKey("e", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            SavePanelAutomation.save(app: app, to: pdfURL, timeout: 20),
            "PDF export save panel never appeared/completed — possible pipeline hang"
        )

        let data = try Data(contentsOf: pdfURL)
        XCTAssertGreaterThan(data.count, 100, "exported PDF is suspiciously small")
        XCTAssertEqual(data.prefix(4), Data("%PDF".utf8), "exported file is not a valid PDF")
    }
}
