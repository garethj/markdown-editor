import XCTest
@testable import MarkdownEditor

final class MarkdownDocumentTests: XCTestCase {

    func testNewDocumentStartsWithNothingUnsaved() {
        let doc = MarkdownDocument(text: "hello")
        XCTAssertEqual(doc.lastConfirmedSavedText, "hello")
        XCTAssertFalse(doc.text != doc.lastConfirmedSavedText, "status bar's dirty check should read false for a fresh document")
    }

    func testEditingWithoutSavingLeavesDirtyFlagSet() {
        let doc = MarkdownDocument(text: "hello")
        doc.text = "hello world"
        XCTAssertTrue(doc.text != doc.lastConfirmedSavedText)
    }

    /// `markSaveConfirmed` only advances on an actual verified read-back — it
    /// must never be inferred from anything else (see CLAUDE.md's save/autosave
    /// notes on why `lastConfirmedSavedText` is the sole source of truth).
    func testMarkSaveConfirmedAdvancesOnlyToGivenText() {
        let doc = MarkdownDocument(text: "hello")
        doc.text = "hello world"
        XCTAssertTrue(doc.text != doc.lastConfirmedSavedText)

        doc.markSaveConfirmed("hello world")
        XCTAssertEqual(doc.lastConfirmedSavedText, "hello world")
        XCTAssertFalse(doc.text != doc.lastConfirmedSavedText)
    }

    func testSnapshotFiresOnWillSaveWithCurrentText() throws {
        let doc = MarkdownDocument(text: "hello")
        doc.text = "hello again"

        var observed: String?
        doc.onWillSave = { observed = $0 }

        let snapshot = try doc.snapshot(contentType: .markdownText)
        XCTAssertEqual(snapshot, "hello again")
        XCTAssertEqual(observed, "hello again")
    }
}
