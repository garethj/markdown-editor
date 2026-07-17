import AppKit
import XCTest

/// Shared helpers for driving the real, built app through XCUITest. These
/// tests take over the physical mouse/keyboard while they run — see
/// CLAUDE.md's "Interactive UI test suite" section for when this suite
/// should be offered and how it must be confirmed with the user first.
enum UITestSupport {

    /// A fresh scratch directory for one test's on-disk files, so tests never
    /// collide and always clean up after themselves.
    static func makeScratchDirectory(function: String = #function) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownEditorUITests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Polls until `element` no longer exists (e.g. a save-panel sheet
    /// dismissing). There's no built-in `waitForNonExistence` on XCUIElement,
    /// so this uses the standard NSPredicate-expectation pattern instead.
    @discardableResult
    static func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Launches the app and guarantees a blank document window. Depending on
    /// the per-app "default new document behavior" preference (unset the
    /// first time an app is launched in a given environment, including under
    /// XCUITest), DocumentGroup's `newDocument:` launch can show the
    /// document-picker "Open" panel instead of a fresh Untitled document —
    /// dismiss it and force one via Cmd+N rather than depend on which one
    /// shows up.
    static func launchWithFreshDocument(_ app: XCUIApplication) {
        app.launch()
        if app.windows["open-panel"].waitForExistence(timeout: 3) {
            // Only force a new document via Cmd+N when launch actually
            // showed the picker — once macOS has recorded a "default new
            // document behavior" preference (which can happen as a
            // side effect of a previous run), later launches open a blank
            // Untitled document automatically, and an unconditional Cmd+N
            // here would create a *second* window on top of it.
            app.typeKey(.escape, modifierFlags: [])
            app.typeKey("n", modifierFlags: .command)
            _ = app.textViews["MarkdownEditorTextView"].waitForExistence(timeout: 5)
            return
        }
        if app.textViews["MarkdownEditorTextView"].waitForExistence(timeout: 5) {
            return
        }
        // Something else is blocking discovery of a blank document window —
        // e.g. session restoration reopening a previous test's document, or
        // an unsaved-changes prompt. Dismiss anything modal and force a
        // fresh document rather than fail outright.
        if app.sheets.firstMatch.exists { app.sheets.firstMatch.buttons.firstMatch.click() }
        if app.dialogs.firstMatch.exists { app.dialogs.firstMatch.buttons.firstMatch.click() }
        app.typeKey("n", modifierFlags: .command)
        _ = app.textViews["MarkdownEditorTextView"].waitForExistence(timeout: 5)
    }

    /// `app.terminate()` returns as soon as the process is asked to die, not
    /// once macOS has finished tearing down its window/session-restoration
    /// state — give it a moment before the next test launches a fresh
    /// instance, or that teardown can race the next launch.
    static func terminateCleanly(_ app: XCUIApplication) {
        app.terminate()
        Thread.sleep(forTimeInterval: 1.0)
    }

    /// Inserts `text` via the pasteboard + Cmd+V rather than `XCUIElement.typeText`,
    /// which synthesizes one real keystroke per character. For any
    /// nontrivial amount of text that's not just slow — MarkdownTextStorage
    /// re-parses the whole document on every keystroke (see CLAUDE.md), so
    /// N synthesized keystrokes cost O(n²), not O(n).
    static func pasteText(_ text: String, into element: XCUIElement, app: XCUIApplication) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        element.click()
        app.typeKey("v", modifierFlags: .command)
    }
}

/// Drives the NSSavePanel sheet used both for "Save As…" and PDF export —
/// both are the same AppKit panel type.
enum SavePanelAutomation {
    /// Waits for the panel, types the full destination path directly into the
    /// filename field (NSSavePanel navigates to an absolute path typed there
    /// rather than requiring the separate Cmd+Shift+G "Go to folder" sheet),
    /// and confirms. Returns whether the panel dismissed within `timeout`.
    @discardableResult
    static func save(app: XCUIApplication, to fileURL: URL, timeout: TimeInterval = 15) -> Bool {
        let sheet = app.sheets.firstMatch
        guard sheet.waitForExistence(timeout: timeout) else { return false }

        let nameField = sheet.textFields["saveAsNameTextField"].exists
            ? sheet.textFields["saveAsNameTextField"]
            : sheet.textFields.firstMatch
        guard nameField.waitForExistence(timeout: timeout) else { return false }
        nameField.click()
        // Route keystrokes through `app`, not the specific field element —
        // XCUITest requires the *queried element itself* to self-report
        // focus for element-scoped typeKey/typeText, which is flakier than
        // just dispatching to whatever currently has keyboard focus.
        app.typeKey("a", modifierFlags: .command) // select the suggested name
        app.typeText(fileURL.path)
        app.typeText("\r")

        if UITestSupport.waitUntilGone(sheet, timeout: 2) {
            return true
        }
        // Typing the path may only have navigated the panel to that
        // directory/filename without confirming — click Save explicitly.
        let saveButton = sheet.buttons["Save"]
        if saveButton.exists {
            saveButton.click()
        }
        return UITestSupport.waitUntilGone(sheet, timeout: timeout)
    }
}

/// Coarse, region-based screenshot comparison — good enough to catch "the
/// view silently jumped to somewhere else" (a real historical bug class:
/// scroll-to-bottom on every keystroke, blockquote bar rendering a line off)
/// without attempting pixel-perfect visual-fidelity assertions, which aren't
/// a good fit for an automated pass/fail gate.
enum PixelSample {
    /// Average per-channel color difference (0...1) between the same pixel
    /// region of two screenshots. Near 0 means "looks the same"; a real
    /// scroll jump replacing the region's content produces a large value.
    static func regionDifference(_ before: XCUIScreenshot, _ after: XCUIScreenshot, rect: CGRect) -> Double {
        guard let beforeRep = bitmap(from: before), let afterRep = bitmap(from: after) else {
            return .infinity
        }
        let x0 = max(0, Int(rect.minX))
        let y0 = max(0, Int(rect.minY))
        let x1 = min(min(beforeRep.pixelsWide, afterRep.pixelsWide), Int(rect.maxX))
        let y1 = min(min(beforeRep.pixelsHigh, afterRep.pixelsHigh), Int(rect.maxY))
        guard x1 > x0, y1 > y0 else { return .infinity }

        var totalDiff: Double = 0
        var sampleCount = 0
        var x = x0
        while x < x1 {
            var y = y0
            while y < y1 {
                if let c1 = beforeRep.colorAt(x: x, y: y), let c2 = afterRep.colorAt(x: x, y: y) {
                    let dr = Double(c1.redComponent) - Double(c2.redComponent)
                    let dg = Double(c1.greenComponent) - Double(c2.greenComponent)
                    let db = Double(c1.blueComponent) - Double(c2.blueComponent)
                    totalDiff += abs(dr) + abs(dg) + abs(db)
                }
                sampleCount += 1
                y += 2 // stride: keep sampling fast, region is small anyway
            }
            x += 2
        }
        guard sampleCount > 0 else { return .infinity }
        return totalDiff / Double(sampleCount)
    }

    private static func bitmap(from screenshot: XCUIScreenshot) -> NSBitmapImageRep? {
        guard let tiff = screenshot.image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
}
