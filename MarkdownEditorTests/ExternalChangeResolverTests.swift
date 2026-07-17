import XCTest
@testable import MarkdownEditor

final class ExternalChangeResolverTests: XCTestCase {

    func testOwnSaveEchoMatchingLastConfirmedIsIgnoredWithoutReconfirming() {
        let resolution = ExternalChangeResolver.resolve(
            newText: "saved",
            currentText: "saved",
            lastConfirmedSavedText: "saved",
            pendingSaveTexts: []
        )
        XCTAssertEqual(resolution, .ignoreOwnEcho(shouldMarkConfirmed: false))
    }

    /// The core `pendingSaveTexts`-is-a-set regression: an older save's disk
    /// echo must still be recognized as our own write even after a *newer*
    /// save has already advanced `lastConfirmedSavedText` past it. A single
    /// shared "expected text" slot would misclassify this as a real conflict.
    func testOlderPendingSaveEchoIsRecognizedAfterNewerSaveConfirmed() {
        let resolution = ExternalChangeResolver.resolve(
            newText: "v1",
            currentText: "v2",
            lastConfirmedSavedText: "v2",
            pendingSaveTexts: ["v1"]
        )
        XCTAssertEqual(resolution, .ignoreOwnEcho(shouldMarkConfirmed: true))
    }

    /// macOS auto-save on focus loss can write back exactly what's already in
    /// memory — this must never trip the conflict dialog.
    func testDiskContentMatchingCurrentDocumentIsIgnored() {
        let resolution = ExternalChangeResolver.resolve(
            newText: "same",
            currentText: "same",
            lastConfirmedSavedText: "different from disk somehow",
            pendingSaveTexts: []
        )
        XCTAssertEqual(resolution, .ignoreMatchesCurrent)
    }

    func testExternalEditWithNoLocalChangesMergesSilently() {
        let resolution = ExternalChangeResolver.resolve(
            newText: "edited externally",
            currentText: "original",
            lastConfirmedSavedText: "original",
            pendingSaveTexts: []
        )
        XCTAssertEqual(resolution, .silentMerge)
    }

    func testExternalEditWithUnsavedLocalChangesIsAConflict() {
        let resolution = ExternalChangeResolver.resolve(
            newText: "edited externally",
            currentText: "edited locally",
            lastConfirmedSavedText: "original",
            pendingSaveTexts: []
        )
        XCTAssertEqual(resolution, .conflict)
    }
}
