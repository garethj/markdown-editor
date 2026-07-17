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

    func testReturnMidLineIsNotIntercepted() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        textView.string = "- item one"
        textView.setSelectedRange(NSRange(location: 4, length: 0)) // inside "item"

        XCTAssertFalse(pressReturn(coordinator, in: textView), "mid-line Return should fall through to default handling")
    }

    func testReturnOnNonListLineIsNotIntercepted() {
        let coordinator = makeCoordinator()
        guard let textView = coordinator.textView else { return XCTFail() }
        setText("just a paragraph", cursorAtEnd: textView)

        XCTAssertFalse(pressReturn(coordinator, in: textView))
        XCTAssertEqual(textView.string, "just a paragraph")
    }
}
