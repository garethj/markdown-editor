import XCTest
@testable import MarkdownEditor

final class MarkdownHTMLRendererTests: XCTestCase {

    private func body(_ markdown: String) -> String {
        MarkdownHTMLRenderer().fullDocument(markdown: markdown)
    }

    func testHeadingLevels() {
        let html = body("# One\n## Two\n### Three\n")
        XCTAssertTrue(html.contains("<h1>One</h1>"))
        XCTAssertTrue(html.contains("<h2>Two</h2>"))
        XCTAssertTrue(html.contains("<h3>Three</h3>"))
    }

    func testUnorderedAndOrderedLists() {
        // Note: the blank line between the two lists makes cmark-gfm render
        // both as "loose" lists (each item's text wrapped in <p>), so match
        // item text by adjacency to a tag boundary rather than assuming a
        // specific tight-list "<li>x</li>" shape.
        let html = body("- a\n- b\n\n1. x\n2. y\n")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("</ul>"))
        XCTAssertTrue(html.contains(">a<"))
        XCTAssertTrue(html.contains(">b<"))
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("</ol>"))
        XCTAssertTrue(html.contains(">x<"))
        XCTAssertTrue(html.contains(">y<"))
    }

    func testTaskListCheckboxes() {
        let html = body("- [ ] todo\n- [x] done\n")
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled>"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked>"))
    }

    func testTable() {
        let html = body("| A | B |\n| --- | --- |\n| 1 | 2 |\n")
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>A</th>"))
        XCTAssertTrue(html.contains("<td>1</td>"))
    }

    func testCodeBlockEscapesHTML() {
        let html = body("```\n<script>alert(1)</script>\n```\n")
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
    }

    func testLinkRendersHref() {
        let html = body("[docs](https://example.com)")
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">docs</a>"))
    }

    func testHighlightSyntaxBecomesMark() {
        let html = body("this is ==important== text")
        XCTAssertTrue(html.contains("<mark>important</mark>"))
    }

    func testBareURLBecomesLink() {
        let html = body("see https://example.com/path for more")
        XCTAssertTrue(html.contains("<a href=\"https://example.com/path\">https://example.com/path</a>"))
    }

    func testStrongEmphasisAndStrikethrough() {
        let html = body("**bold** _italic_ ~~gone~~")
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
        XCTAssertTrue(html.contains("<del>gone</del>"))
    }
}
