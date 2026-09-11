import XCTest
@testable import MarkdownEditor

/// Benchmarks the per-keystroke editing pipeline against documents of
/// increasing size, and guards the scaling behaviour that makes large
/// documents feel slow.
///
/// The pipeline under test is the one described in CLAUDE.md's "Data flow on
/// every keystroke": `replaceCharacters` → `processEditing` →
/// `applyMarkdownStyling` → a full `MarkdownStyleMap(text:)` re-parse. The
/// full re-parse is unavoidable (cmark can't parse incrementally), but it
/// should be *linear* in document length. Anything super-linear means typing
/// gets disproportionately worse as a file grows, which is the symptom
/// being chased here.
final class EditingPerformanceTests: XCTestCase {

    // MARK: - Corpus generation

    /// A prose-and-inline-formatting document: the common case.
    private func proseDocument(sections: Int) -> String {
        var out = ""
        for i in 0..<sections {
            out += "## Section \(i)\n\n"
            out += "Some **bold text** and _italic text_ and `inline code` in a paragraph "
            out += "with a [link](https://example.com/page/\(i)) and some more trailing words.\n\n"
            out += "- A list item with **emphasis**\n"
            out += "- Another item with `code`\n"
            out += "- A third item with a [link](https://example.com/\(i))\n\n"
            out += "> A blockquote line with _emphasis_ inside it.\n\n"
        }
        return out
    }

    /// A table-heavy document: tables generate far more StyledElements per
    /// character than prose (one per cell, plus a kern element per cell).
    private func tableDocument(rows: Int) -> String {
        var out = "# Table document\n\n| Name | Value | Notes | Owner |\n|---|---|---|---|\n"
        for i in 0..<rows {
            out += "| item \(i) | **\(i * 7)** | some `note` text here | owner-\(i) |\n"
        }
        return out + "\n"
    }

    /// A list-heavy document with short items. This is the shape that
    /// reproduces the reported slowness most sharply: cost here is driven by
    /// the *number of list items*, not the document's length, because
    /// `StyleWalker.appendListContinuationIndent` lays out each item's marker
    /// prefix with CoreText to measure its width.
    private func listDocument(items: Int) -> String {
        var out = "# List document\n\n"
        for i in 0..<items {
            if i % 30 == 0 { out += "\n## Group \(i / 30)\n\n" }
            out += "  - Item \(i) (n tracks)\n"
        }
        return out
    }

    // MARK: - Measurement helpers

    private func timeSeconds(_ iterations: Int = 1, _ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { body() }
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000.0 / Double(iterations)
    }

    /// Time for one realistic keystroke: inserting a single character near the
    /// middle of the document, through the real text-storage edit pipeline.
    private func keystrokeSeconds(_ text: String, iterations: Int = 5) -> Double {
        let storage = MarkdownTextStorage()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        let ns = storage.string as NSString
        // Insert at a paragraph-interior position roughly halfway in.
        let insertAt = max(0, min(ns.length, ns.length / 2))
        return timeSeconds(iterations) {
            storage.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: "x")
        }
    }

    private func parseSeconds(_ text: String, iterations: Int = 5) -> Double {
        timeSeconds(iterations) { _ = MarkdownStyleMap(text: text) }
    }

    // MARK: - Benchmarks

    func testParseScalingWithDocumentSize() {
        print("\n=== MarkdownStyleMap(text:) full parse ===")
        print("     chars   elements     parse ms  ms/10k chars")
        for sections in [8, 16, 32, 64, 128] {
            let doc = proseDocument(sections: sections)
            let chars = (doc as NSString).length
            let elements = MarkdownStyleMap(text: doc).elements.count
            let ms = parseSeconds(doc) * 1000
            print(String(format: "%10d %10d %12.2f %12.2f",
                         chars, elements, ms, ms / (Double(chars) / 10_000)))
        }
    }

    func testKeystrokeScalingWithDocumentSize() {
        print("\n=== Single keystroke through MarkdownTextStorage (prose) ===")
        print("     chars  keystroke ms  ms/10k chars")
        for sections in [8, 16, 32, 64, 128] {
            let doc = proseDocument(sections: sections)
            let chars = (doc as NSString).length
            let ms = keystrokeSeconds(doc) * 1000
            print(String(format: "%10d %12.2f %12.2f", chars, ms, ms / (Double(chars) / 10_000)))
        }
    }

    func testKeystrokeScalingWithTables() {
        print("\n=== Single keystroke through MarkdownTextStorage (tables) ===")
        print("     chars   elements  keystroke ms  ms/10k chars")
        for rows in [25, 50, 100, 200] {
            let doc = tableDocument(rows: rows)
            let chars = (doc as NSString).length
            let elements = MarkdownStyleMap(text: doc).elements.count
            let ms = keystrokeSeconds(doc, iterations: 3) * 1000
            print(String(format: "%10d %10d %12.2f %12.2f",
                         chars, elements, ms, ms / (Double(chars) / 10_000)))
        }
    }

    /// The scaling guard. Doubling the document length should roughly double
    /// the per-keystroke cost, not quadruple it. A ratio near 4 means the
    /// pipeline is quadratic in document length.
    func testKeystrokeCostScalesRoughlyLinearly() {
        let small = proseDocument(sections: 32)
        let large = proseDocument(sections: 64)
        let smallChars = Double((small as NSString).length)
        let largeChars = Double((large as NSString).length)

        // Warm up so first-parse/font-cache costs don't land in the measurement.
        _ = keystrokeSeconds(small, iterations: 2)

        let smallMs = keystrokeSeconds(small) * 1000
        let largeMs = keystrokeSeconds(large) * 1000
        let sizeRatio = largeChars / smallChars
        let costRatio = largeMs / smallMs
        // Cost growth per unit of size growth: 1.0 == perfectly linear,
        // 2.0 == quadratic.
        let exponentProxy = costRatio / sizeRatio

        print(String(format: "\n=== Scaling: %.0f chars %.2f ms → %.0f chars %.2f ms (size ×%.2f, cost ×%.2f, per-char growth ×%.2f) ===",
                     smallChars, smallMs, largeChars, largeMs, sizeRatio, costRatio, exponentProxy))

        XCTAssertLessThan(exponentProxy, 1.6,
                          "Per-keystroke cost is growing faster than document length — the edit pipeline is super-linear.")
    }

    /// An absolute-budget guard on a document the size of a long README or
    /// spec. 16ms is one 60Hz frame; typing should comfortably fit inside one.
    func testKeystrokeBudgetOnRealisticDocument() {
        let doc = proseDocument(sections: 64) // ~25KB, a long but ordinary file
        _ = keystrokeSeconds(doc, iterations: 2) // warm up
        let ms = keystrokeSeconds(doc) * 1000
        print(String(format: "\n=== Keystroke on %d chars: %.2f ms ===", (doc as NSString).length, ms))
        // Deliberately loose. This runs in the pre-commit suite, so it is a
        // gross-regression guard, not a frame-budget assertion — the measured
        // value at the time of writing is ~9 ms in a Debug build, so there is
        // ~4x headroom before this trips on an unrelated machine hiccup.
        XCTAssertLessThan(ms, 40.0, "A single keystroke got dramatically slower on an ordinary-sized document.")
    }

    // MARK: - Dirty-region locality

    /// `applyMarkdownStyling` widens its dirty region to the full range of any
    /// element that intersects it. A table (or any other long single block)
    /// contributes one element spanning the *whole* block, so a keystroke
    /// anywhere inside it widens the "incremental" restyle to the entire
    /// block — attribute resets, font-trait merging, both regex passes and
    /// the emoji-font scan all re-run across it. This measures how much that
    /// costs compared with the same keystroke in ordinary prose in the very
    /// same document.
    func testKeystrokeCostInsideLargeBlockVersusProse() {
        func keystroke(in text: String, at insertAt: Int, iterations: Int = 5) -> Double {
            let storage = MarkdownTextStorage()
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
            return timeSeconds(iterations) {
                storage.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: "x")
            }
        }

        let prose = proseDocument(sections: 20)
        let table = tableDocument(rows: 200)
        let doc = prose + table
        let ns = doc as NSString
        let proseSpot = (prose as NSString).length / 2
        let tableSpot = (prose as NSString).length + ns.range(of: "| item 100 ").length + 200

        let proseMs = keystroke(in: doc, at: proseSpot) * 1000
        let tableMs = keystroke(in: doc, at: min(tableSpot, ns.length)) * 1000

        print(String(format: "\n=== Same %d-char document: keystroke in prose %.2f ms vs inside a 200-row table %.2f ms (%.1fx) ===",
                     ns.length, proseMs, tableMs, tableMs / proseMs))

        // A long blockquote is the same shape of problem.
        var quote = "# Quote doc\n\n"
        for i in 0..<300 { quote += "> Quoted line \(i) with some **bold** words in it.\n" }
        let quoteDoc = prose + "\n\n" + quote
        let quoteNS = quoteDoc as NSString
        let quoteSpot = quoteNS.range(of: "Quoted line 150").location + 5
        let quoteProseMs = keystroke(in: quoteDoc, at: proseSpot) * 1000
        let quoteMs = keystroke(in: quoteDoc, at: quoteSpot) * 1000
        print(String(format: "=== Same %d-char document: keystroke in prose %.2f ms vs inside a 300-line blockquote %.2f ms (%.1fx) ===",
                     quoteNS.length, quoteProseMs, quoteMs, quoteMs / quoteProseMs))
    }

    /// Cost per list item, isolated. Every list item pays for an
    /// `NSAttributedString.size()` CoreText measurement of its marker prefix,
    /// whose result is then discarded for any line shorter than 60 characters
    /// — which short list items always are.
    func testCostPerListItem() {
        print("\n=== List-heavy document (cost is per item, not per character) ===")
        print("     items      chars    parse ms   µs/item")
        for items in [250, 500, 1000, 2000] {
            let doc = listDocument(items: items)
            let chars = (doc as NSString).length
            let ms = parseSeconds(doc, iterations: 3) * 1000
            print(String(format: "%10d %10d %11.2f %9.1f",
                         items, chars, ms, ms * 1000 / Double(items)))
        }
    }
}
