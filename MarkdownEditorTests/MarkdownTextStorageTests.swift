import XCTest
@testable import MarkdownEditor

final class MarkdownTextStorageTests: XCTestCase {

    private func makeStorage(_ text: String) -> MarkdownTextStorage {
        let storage = MarkdownTextStorage()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        return storage
    }

    private func attributes(at index: Int, in storage: MarkdownTextStorage) -> [NSAttributedString.Key: Any] {
        storage.attributes(at: index, effectiveRange: nil)
    }

    func testInitialFullParseAppliesBoldAttributes() {
        let source = "Hello **world**"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "world").location
        let font = attributes(at: idx, in: storage)[.font] as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    /// Regression coverage for `mergeFontTraits`: nesting bold inside italic
    /// (or vice versa) must produce a single merged bold-italic font, not
    /// just whichever formatting was applied last.
    /// Regression: the rounded system design used for bold body text (see
    /// MarkdownTheme.roundedFont) has no true italic face — merging bold
    /// (rounded) with italic used to silently drop the italic trait rather
    /// than falling back to a descriptor that actually has one.
    func testNestedBoldInsideItalicMergesToBoldItalicFont() {
        let source = "_text **bold** text_"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "bold").location
        let traits = (attributes(at: idx, in: storage)[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold))
        XCTAssertTrue(traits.contains(.italic))
    }

    func testNestedItalicInsideBoldMergesToBoldItalicFont() {
        let source = "**text _italic_ text**"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "italic").location
        let traits = (attributes(at: idx, in: storage)[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold))
        XCTAssertTrue(traits.contains(.italic))
    }

    func testTripleAsteriskEmphasisMergesToBoldItalicFont() {
        let source = "***bold italic***"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "bold").location
        let traits = (attributes(at: idx, in: storage)[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold))
        XCTAssertTrue(traits.contains(.italic))
    }

    func testFencedCodeBlockAppliesMonospaceFont() {
        let source = "```\nlet x = 1\n```\n"
        let storage = makeStorage(source)
        let idx = (source as NSString).range(of: "let x").location
        let traits = (attributes(at: idx, in: storage)[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.monoSpace))
    }

    /// Regression: a compound construct (blockquote) has one wide "whole
    /// block" element plus one small colored "> " marker element per line.
    /// Editing only line two must not cause line one's marker color to be
    /// dropped when the wide element's re-application wins the race over a
    /// too-narrow dirty region.
    func testEditingOneBlockquoteLineDoesNotLoseAnotherLinesMarkerColor() {
        let storage = makeStorage("> line one\n> line two\n")
        XCTAssertEqual(markerColor(in: storage, lineIndex: 0), MarkdownTheme.shared.linkColor)

        // Edit scoped to line two only: append a character at its end.
        let lineTwoEnd = (storage.string as NSString).length - 1 // before trailing "\n"
        storage.replaceCharacters(in: NSRange(location: lineTwoEnd, length: 0), with: "!")

        XCTAssertEqual(
            markerColor(in: storage, lineIndex: 0), MarkdownTheme.shared.linkColor,
            "line one's '>' marker color must survive an edit scoped to line two"
        )
    }

    /// Regression: deleting a Setext heading's "===" underline must revert the
    /// text line above it back to plain-paragraph styling, even though the
    /// edit itself only touches the underline's own line.
    func testDeletingSetextUnderlineRevertsHeadingLineToPlainFont() {
        let storage = makeStorage("Heading\n===\nbody\n")
        let headingFont = attributes(at: 0, in: storage)[.font] as? NSFont
        XCTAssertEqual(headingFont?.pointSize, MarkdownTheme.shared.headingFonts[0].pointSize)
        XCTAssertTrue(headingFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)

        let underlineRange = (storage.string as NSString).range(of: "===\n")
        XCTAssertNotEqual(underlineRange.location, NSNotFound)
        storage.replaceCharacters(in: underlineRange, with: "")

        let revertedFont = attributes(at: 0, in: storage)[.font] as? NSFont
        XCTAssertEqual(revertedFont?.pointSize, MarkdownTheme.shared.defaultFont.pointSize)
        XCTAssertFalse(revertedFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? true)
    }

    private func markerColor(in storage: MarkdownTextStorage, lineIndex: Int) -> NSColor? {
        let lines = storage.string.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return nil }
        var offset = 0
        for i in 0..<lineIndex {
            offset += (lines[i] as NSString).length + 1
        }
        let nsText = storage.string as NSString
        guard offset < nsText.length, nsText.character(at: offset) == UInt16(UnicodeScalar(">").value) else {
            return nil
        }
        return attributes(at: offset, in: storage)[.foregroundColor] as? NSColor
    }
}
