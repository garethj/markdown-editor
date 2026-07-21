import XCTest
@testable import MarkdownEditor

/// Drives `MarkdownTextView.Coordinator`'s Return-key handling through its
/// `NSTextViewDelegate` entry point (`textView(_:doCommandBy:)`), the same
/// path AppKit uses when the user presses Return. No window is needed —
/// `NSTextView` manipulates its own text storage directly.
final class ListContinuationTests: XCTestCase {

    private func makeCoordinator() -> MarkdownTextView.Coordinator {
        let parent = MarkdownTextView(document: MarkdownDocument(), fileURL: nil, undoManager: nil, tocModel: nil)
        let coordinator = MarkdownTextView.Coordinator(parent)
        let textView = EditorTextView(frame: .zero)
        coordinator.textView = textView
        return coordinator
    }

    private func pressReturn(_ coordinator: MarkdownTextView.Coordinator, in textView: NSTextView) -> Bool {
        coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    }

    private func setText(_ text: String, cursorAtEnd textView: NSTextView) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    func testReturnContinuesUnorderedList() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        setText("- item one", cursorAtEnd: textView)

        XCTAssertTrue(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "- item one\n- ")
    }

    func testReturnContinuesOrderedListWithRenumbering() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        setText("1. first", cursorAtEnd: textView)

        XCTAssertTrue(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "1. first\n2. ")
    }

    func testReturnOnEmptyItemExitsList() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        setText("- item one\n- ", cursorAtEnd: textView)

        XCTAssertTrue(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "- item one\n")
    }

    func testReturnCarriesCheckboxMarkerToNextItem() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        setText("- [ ] task", cursorAtEnd: textView)

        XCTAssertTrue(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "- [ ] task\n- [ ] ")
    }

    func testReturnCarriesCheckedCheckboxAsUncheckedOnNextItem() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        setText("- [x] done", cursorAtEnd: textView)

        XCTAssertTrue(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "- [x] done\n- [ ] ")
    }

    func testReturnMidLineSplitsUnorderedItemWithNewBullet() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        textView.string = "- item one"
        textView.setSelectedRange(NSRange(location: 4, length: 0)) // "- it|em one"

        XCTAssertTrue(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "- it\n- em one")
    }

    func testReturnMidLineSplitsOrderedItemWithNextNumber() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        textView.string = "1. first item"
        textView.setSelectedRange(NSRange(location: 4, length: 0)) // "1. f|irst item"

        XCTAssertTrue(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "1. f\n2. irst item")
    }

    func testReturnMidLineCarriesCheckboxMarkerToSplitItem() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        textView.string = "- [ ] task one"
        textView.setSelectedRange(NSRange(location: 7, length: 0)) // "- [ ] t|ask one"

        XCTAssertTrue(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "- [ ] t\n- [ ] ask one")
    }

    func testReturnInsideMarkerIsNotIntercepted() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        textView.string = "- item one"
        textView.setSelectedRange(NSRange(location: 1, length: 0)) // "-| item one", before the marker's space

        XCTAssertFalse(pressReturn(coordinator, in: textView), "Return inside the marker/indent should fall through to default handling")
    }

    func testReturnOnNonListLineIsNotIntercepted() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        setText("just a paragraph", cursorAtEnd: textView)

        XCTAssertFalse(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "just a paragraph")
    }
}
