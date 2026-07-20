import AppKit
import Markdown

// MARK: - Custom attribute keys

extension NSAttributedString.Key {
    /// Stores the destination URL string for markdown links.
    static let markdownLinkURL = NSAttributedString.Key("markdownLinkURL")
}

// MARK: - Styled element produced by AST walk

struct StyledElement {
    let fullRange: NSRange
    let contentRange: NSRange
    let delimiterRanges: [NSRange]
    let attributes: [NSAttributedString.Key: Any]
}

// MARK: - Source range → NSRange conversion

struct SourceRangeConverter {
    private let string: String
    let fullString: String
    private let lineStartUTF8Offsets: [Int] // UTF-8 byte offset of each line start

    init(_ string: String) {
        self.string = string
        self.fullString = string
        var offsets: [Int] = [0]
        var byteOffset = 0
        for scalar in string.unicodeScalars {
            let len = scalar.utf8.count
            byteOffset += len
            if scalar == "\n" {
                offsets.append(byteOffset)
            }
        }
        self.lineStartUTF8Offsets = offsets
    }

    private func utf8Offset(for location: SourceLocation) -> Int? {
        let line = location.line - 1
        let column = location.column - 1
        guard line >= 0, line < lineStartUTF8Offsets.count, column >= 0 else { return nil }
        return lineStartUTF8Offsets[line] + column
    }

    func nsRange(for sourceRange: SourceRange) -> NSRange? {
        guard let startUTF8 = utf8Offset(for: sourceRange.lowerBound),
              let endUTF8 = utf8Offset(for: sourceRange.upperBound)
        else { return nil }

        let utf8View = string.utf8
        guard startUTF8 >= 0, startUTF8 <= utf8View.count,
              endUTF8 >= 0, endUTF8 <= utf8View.count,
              startUTF8 <= endUTF8
        else { return nil }

        let startIdx = utf8View.index(utf8View.startIndex, offsetBy: startUTF8)
        let endIdx = utf8View.index(utf8View.startIndex, offsetBy: endUTF8)

        // NSRange(_:in:) correctly converts String.Index range to UTF-16 based NSRange
        return NSRange(startIdx..<endIdx, in: string)
    }
}

// MARK: - Style map

final class MarkdownStyleMap {
    private(set) var elements: [StyledElement]
    private(set) var allDelimiterRanges: [NSRange]
    /// Table regions with their required pixel width for horizontal scrolling.
    private(set) var tableRegions: [(charRange: NSRange, requiredWidth: CGFloat)]
    /// Task-list checkbox bracket ranges (e.g. the 3 characters "[ ]" or "[x]"), for click-to-toggle.
    private(set) var checkboxes: [(range: NSRange, checked: Bool)]
    /// Headings in document order, for the table of contents.
    private(set) var headings: [(range: NSRange, level: Int, title: String)]

    init(text: String) {
        guard !text.isEmpty else {
            self.elements = []
            self.allDelimiterRanges = []
            self.tableRegions = []
            self.checkboxes = []
            self.headings = []
            return
        }
        let doc = Document(parsing: text)
        let conv = SourceRangeConverter(text)
        let len = (text as NSString).length
        var walker = StyleWalker(converter: conv, textLength: len)
        walker.visit(doc)
        // Cursor-reveal (MarkdownTextView.Coordinator.updateCursorReveal) binary-searches
        // this array assuming it's sorted by fullRange.location. That's usually true from
        // depth-first AST traversal alone, but table visiting breaks it: it appends its own
        // bookkeeping elements (kern, header, pipe color) for the whole table before
        // descending into cell content, so a nested Strong/Emphasis element inside an
        // earlier cell ends up appended after — and thus positioned after in the array —
        // elements for later cells it actually precedes in the document. Sorting once here
        // is cheaper than making every visitor prove it appends in strict document order.
        self.elements = walker.elements.sorted { $0.fullRange.location < $1.fullRange.location }
        self.allDelimiterRanges = walker.elements.flatMap(\.delimiterRanges)
        self.tableRegions = walker.tableRegions
        self.checkboxes = walker.checkboxes
        self.headings = walker.headings
    }

    func appendElements(_ newElements: [StyledElement]) {
        elements.append(contentsOf: newElements)
        elements.sort { $0.fullRange.location < $1.fullRange.location }
        allDelimiterRanges.append(contentsOf: newElements.flatMap(\.delimiterRanges))
    }

}

// MARK: - AST walker

private struct StyleWalker: MarkupWalker {
    let converter: SourceRangeConverter
    let textLength: Int
    var elements: [StyledElement] = []
    var tableRegions: [(charRange: NSRange, requiredWidth: CGFloat)] = []
    var checkboxes: [(range: NSRange, checked: Bool)] = []
    var headings: [(range: NSRange, level: Int, title: String)] = []

    // MARK: - Headings

    mutating func visitHeading(_ heading: Heading) {
        guard let sourceRange = heading.range,
              let nsRange = converter.nsRange(for: sourceRange),
              nsRange.location + nsRange.length <= textLength
        else {
            descendInto(heading)
            return
        }

        let level = heading.level
        let text = converter.fullString as NSString
        let isATX = text.character(at: nsRange.location) == Self.hashUTF16

        let delimiterRange: NSRange
        let contentRange: NSRange
        var elementRange = nsRange
        var closingSequenceRange: NSRange?
        if isATX {
            let delimiterLength = min(level + 1, nsRange.length) // "## " = level + space
            delimiterRange = NSRange(location: nsRange.location, length: delimiterLength)
            contentRange = NSRange(location: nsRange.location + delimiterLength,
                                   length: max(0, nsRange.length - delimiterLength))
            // ATX headings support an optional closing sequence of #s (e.g.
            // "# Heading #"), which CommonMark requires to be preceded by a
            // space and followed only by spaces/tabs to the end of the line.
            // cmark strips that closing sequence — and any trailing
            // whitespace before it — from heading.range's own upper bound,
            // the same way it strips the leading "# " from the lower bound,
            // so nsRange already ends exactly at the real content. Whatever
            // characters remain between there and the end of the physical
            // line (if any) can only be that closing sequence, so hide it
            // too, matching the leading delimiter's treatment — otherwise it
            // shows up as plain, unstyled, un-hidden trailing text.
            let lineRange = text.lineRange(for: NSRange(location: nsRange.location, length: 0))
            let lineEnd = Self.lineEndExcludingTerminator(text, lineRange)
            if lineEnd > NSMaxRange(nsRange) {
                closingSequenceRange = NSRange(location: NSMaxRange(nsRange), length: lineEnd - NSMaxRange(nsRange))
                elementRange = NSRange(location: nsRange.location, length: lineEnd - nsRange.location)
            }
        } else {
            // Setext heading: CommonMark allows "one or more lines of text" as
            // content before the underline, not just a single line — e.g.
            // "Test\nHeading\n---" (no blank line before it) makes "Test" AND
            // "Heading" both part of the heading's content, with "---" as the
            // underline. Assuming content was always exactly the first line
            // used to mistake a second content line for the underline itself
            // (recoloring it and giving it the underline's paragraph spacing)
            // while the real underline fell outside the element range
            // entirely and rendered with no heading styling at all. So: scan
            // forward line by line from the start looking for the underline
            // itself — a line composed only of "=" (level 1) or only of "-"
            // (level 2+), matching how cmark itself decides where a setext
            // heading's content ends.
            //
            // When no blank line separates the heading from whatever follows
            // it, swift-markdown's reported nsRange can extend past the
            // underline into that next block, so the scan is capped at
            // nsRange's own upper bound rather than trusted past it.
            let underlineChar: UInt16 = level == 1 ? Self.equalsUTF16 : Self.dashUTF16
            var delimStart = nsRange.location
            var delimEnd = NSMaxRange(nsRange)
            var cursor = nsRange.location
            while cursor < NSMaxRange(nsRange) {
                let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
                if Self.isSetextUnderlineLine(text, lineRange, char: underlineChar) {
                    delimStart = lineRange.location
                    delimEnd = min(NSMaxRange(lineRange), NSMaxRange(nsRange))
                    break
                }
                let next = NSMaxRange(lineRange)
                guard next > cursor else { break } // defensive: never loop forever
                cursor = next
            }
            contentRange = NSRange(location: nsRange.location, length: max(0, delimStart - nsRange.location))
            delimiterRange = NSRange(location: delimStart, length: max(0, delimEnd - delimStart))
            elementRange = NSRange(location: nsRange.location, length: delimEnd - nsRange.location)
        }

        // The ATX "#" prefix carries no reading value once the font size
        // already signals the level, so it stays hidden like a bold/italic
        // delimiter. The Setext "==="/"---" underline is different — unlike
        // "#", it's the only thing distinguishing an H1 from an H2 in that
        // syntax, so (like blockquote's ">" or a table's pipes) it stays
        // visible, recolored to the accent color instead of hidden. It still
        // inherits the heading's own font from the element below (only the
        // color is overridden here), so its size continues to track heading
        // level exactly as the text line's does.
        //
        // For Setext, the base element below uses headingSetextContentAttributes
        // rather than headingAttributes — the content (text) line and the
        // underline line are two separate NSTextView paragraphs even though
        // they're one markdown node, so applying the same before-and-after
        // paragraph spacing to both double-counts the gap between them (see
        // that function's doc comment). The underline element that follows
        // overrides its own paragraph spacing back to the correct halves.
        elements.append(StyledElement(
            fullRange: elementRange,
            contentRange: contentRange,
            delimiterRanges: isATX ? [delimiterRange] + (closingSequenceRange.map { [$0] } ?? []) : [],
            attributes: isATX
                ? MarkdownTheme.shared.headingAttributes(level: level)
                : MarkdownTheme.shared.headingSetextContentAttributes(level: level, isFirstLine: true)
        ))
        if !isATX {
            // If content spans more than one physical line, only the first
            // one should carry the block's "gap above" spacing (applied
            // uniformly above via the base element) — a second content line
            // getting that same spacing would open an unwanted gap between
            // it and the line before it, inside what's meant to read as one
            // tight heading block.
            let firstContentLineRange = text.lineRange(for: NSRange(location: contentRange.location, length: 0))
            let firstContentLineEnd = min(NSMaxRange(firstContentLineRange), NSMaxRange(contentRange))
            if firstContentLineEnd < NSMaxRange(contentRange) {
                let continuationRange = NSRange(location: firstContentLineEnd, length: NSMaxRange(contentRange) - firstContentLineEnd)
                elements.append(StyledElement(
                    fullRange: continuationRange,
                    contentRange: continuationRange,
                    delimiterRanges: [],
                    attributes: MarkdownTheme.shared.headingSetextContentAttributes(level: level, isFirstLine: false)
                ))
            }
            if delimiterRange.length > 0 {
                elements.append(StyledElement(
                    fullRange: delimiterRange,
                    contentRange: delimiterRange,
                    delimiterRanges: [],
                    attributes: MarkdownTheme.shared.headingUnderlineAttributes(level: level)
                ))
            }
        }
        headings.append((
            range: elementRange,
            level: level,
            title: heading.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        descendInto(heading)
    }

    private static let hashUTF16 = UInt16(UnicodeScalar("#").value)
    private static let equalsUTF16 = UInt16(UnicodeScalar("=").value)
    private static let dashUTF16 = UInt16(UnicodeScalar("-").value)

    /// True if `lineRange` (an `NSString.lineRange` result, so it includes
    /// the trailing line terminator) consists only of `char` and spaces/tabs
    /// — i.e. a Setext underline line ("===" or "---"), matching how cmark
    /// itself recognizes one.
    private static func isSetextUnderlineLine(_ text: NSString, _ lineRange: NSRange, char: UInt16) -> Bool {
        var sawChar = false
        var i = lineRange.location
        let end = NSMaxRange(lineRange)
        while i < end {
            let c = text.character(at: i)
            if c == 10 || c == 13 { break } // \n or \r
            if c == char {
                sawChar = true
            } else if c != 32 && c != 9 { // not a space or tab
                return false
            }
            i += 1
        }
        return sawChar
    }

    /// `lineRange` (an `NSString.lineRange` result) includes the trailing
    /// line terminator ("\n", "\r\n", or "\r") — this returns the index just
    /// before it, i.e. the end of the line's actual content.
    private static func lineEndExcludingTerminator(_ text: NSString, _ lineRange: NSRange) -> Int {
        var end = NSMaxRange(lineRange)
        guard end > lineRange.location else { return end }
        let last = text.character(at: end - 1)
        if last == 10 { // "\n"
            end -= 1
            if end > lineRange.location, text.character(at: end - 1) == 13 { end -= 1 } // "\r\n"
        } else if last == 13 { // "\r"
            end -= 1
        }
        return end
    }

    // MARK: - Bold

    mutating func visitStrong(_ strong: Strong) {
        guard let sourceRange = strong.range,
              let nsRange = converter.nsRange(for: sourceRange),
              nsRange.length >= 4,
              nsRange.location + nsRange.length <= textLength
        else {
            descendInto(strong)
            return
        }

        let delimiterRanges: [NSRange]
        let contentRange: NSRange
        if let ambiguous = ambiguousTripleEmphasisPartner(of: strong, siblingRange: nsRange, as: Emphasis.self) {
            (delimiterRanges, contentRange) = ambiguous
        } else {
            let openDelim = NSRange(location: nsRange.location, length: 2)
            let closeDelim = NSRange(location: NSMaxRange(nsRange) - 2, length: 2)
            delimiterRanges = [openDelim, closeDelim]
            contentRange = NSRange(location: nsRange.location + 2, length: nsRange.length - 4)
        }

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: delimiterRanges,
            attributes: MarkdownTheme.shared.boldAttributes
        ))
        descendInto(strong)
    }

    // MARK: - Italic

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        guard let sourceRange = emphasis.range,
              let nsRange = converter.nsRange(for: sourceRange),
              nsRange.length >= 2,
              nsRange.location + nsRange.length <= textLength
        else {
            descendInto(emphasis)
            return
        }

        let delimiterRanges: [NSRange]
        let contentRange: NSRange
        if let ambiguous = ambiguousTripleEmphasisPartner(of: emphasis, siblingRange: nsRange, as: Strong.self) {
            (delimiterRanges, contentRange) = ambiguous
        } else {
            let openDelim = NSRange(location: nsRange.location, length: 1)
            let closeDelim = NSRange(location: NSMaxRange(nsRange) - 1, length: 1)
            delimiterRanges = [openDelim, closeDelim]
            contentRange = NSRange(location: nsRange.location + 1, length: nsRange.length - 2)
        }

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: delimiterRanges,
            attributes: MarkdownTheme.shared.italicAttributes
        ))
        descendInto(emphasis)
    }

    /// "***text***" is ambiguous: cmark reports the Strong and its nested
    /// Emphasis (or vice versa) as spanning the *identical* source range,
    /// rather than one properly nested inside the other. Naively letting
    /// each side hide its own fixed-width delimiter from that shared
    /// range's edges double-counts one edge character and leaves the
    /// innermost marker on each side visible. When detected, whichever node
    /// is the true AST *parent* of the pair claims the full combined
    /// 3-character run on each side; the nested child claims none — but
    /// both still contribute their own attributes (bold/italic) over the
    /// same, correctly-trimmed content, so the merge still produces
    /// bold-italic text.
    private func ambiguousTripleEmphasisPartner<Sibling: Markup>(
        of node: Markup, siblingRange: NSRange, as siblingType: Sibling.Type
    ) -> ([NSRange], NSRange)? {
        func rangeMatches(_ sibling: Sibling?) -> Bool {
            guard let sibling, let sourceRange = sibling.range,
                  let ns = converter.nsRange(for: sourceRange) else { return false }
            return ns == siblingRange
        }

        // MarkupChildren is only a Sequence, not a Collection, so it has no
        // plain `.first` property — `.first` alone resolves ambiguously to
        // the `first(where:)` method reference rather than an element.
        // `next()` mutates the iterator's internal state, so it needs a var.
        var childIterator = node.children.makeIterator()
        let firstChild = childIterator.next()
        let isOuter = rangeMatches(firstChild as? Sibling)
        let isInner = rangeMatches(node.parent as? Sibling)
        guard isOuter || isInner else { return nil }

        let contentRange = NSRange(location: siblingRange.location + 3, length: max(0, siblingRange.length - 6))
        let delimiterRanges: [NSRange] = isOuter
            ? [NSRange(location: siblingRange.location, length: 3), NSRange(location: NSMaxRange(siblingRange) - 3, length: 3)]
            : []
        return (delimiterRanges, contentRange)
    }

    // MARK: - Inline code

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let sourceRange = inlineCode.range,
              let nsRange = converter.nsRange(for: sourceRange),
              nsRange.length >= 2,
              nsRange.location + nsRange.length <= textLength
        else { return }

        let openDelim = NSRange(location: nsRange.location, length: 1)
        let closeDelim = NSRange(location: NSMaxRange(nsRange) - 1, length: 1)
        let contentRange = NSRange(location: nsRange.location + 1, length: nsRange.length - 2)

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: [openDelim, closeDelim],
            attributes: MarkdownTheme.shared.inlineCodeAttributes
        ))
    }

    // MARK: - Code blocks

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let sourceRange = codeBlock.range,
              let nsRange = converter.nsRange(for: sourceRange),
              nsRange.location + nsRange.length <= textLength
        else { return }

        // For fenced code blocks, the entire block including fences gets code styling.
        // We hide the opening and closing fence lines as delimiters.
        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: nsRange,
            delimiterRanges: [],
            attributes: MarkdownTheme.shared.codeBlockAttributes
        ))
    }

    // MARK: - Thematic breaks

    /// A thematic break ("---"/"***"/"___") is the purest case of "the whole
    /// line is the delimiter" — same principle as blockquote/table markers:
    /// visible, colored with the accent color, not hidden.
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let sourceRange = thematicBreak.range,
              let nsRange = converter.nsRange(for: sourceRange),
              nsRange.location + nsRange.length <= textLength
        else { return }

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: nsRange,
            delimiterRanges: [],
            attributes: MarkdownTheme.shared.thematicBreakAttributes
        ))
    }

    // MARK: - Links

    mutating func visitLink(_ link: Link) {
        guard let sourceRange = link.range,
              let nsRange = converter.nsRange(for: sourceRange),
              nsRange.length >= 4,
              nsRange.location + nsRange.length <= textLength
        else {
            descendInto(link)
            return
        }

        // Link format: [text](url)
        // Find the ]( boundary by looking at children
        // The opening [ is 1 char, then text, then ](url)
        let openBracket = NSRange(location: nsRange.location, length: 1)

        // Find where link text ends - look for first child text range
        var textEndOffset = nsRange.location + 1
        for child in link.children {
            if let childRange = child.range,
               let childNS = converter.nsRange(for: childRange) {
                textEndOffset = NSMaxRange(childNS)
            }
        }

        let closingDelimStart = textEndOffset
        let closingDelimLength = NSMaxRange(nsRange) - closingDelimStart
        let closeDelim = NSRange(location: closingDelimStart, length: closingDelimLength)
        let contentRange = NSRange(location: nsRange.location + 1,
                                   length: textEndOffset - (nsRange.location + 1))

        var attrs = MarkdownTheme.shared.linkAttributes
        if let destination = link.destination, !destination.isEmpty {
            attrs[.markdownLinkURL] = destination
        }

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: [openBracket, closeDelim],
            attributes: attrs
        ))
        descendInto(link)
    }

    // MARK: - Lists: bullets, numbers, and task checkboxes

    mutating func visitListItem(_ listItem: ListItem) {
        defer { descendInto(listItem) }

        guard let sourceRange = listItem.range,
              let itemNS = converter.nsRange(for: sourceRange),
              itemNS.location + itemNS.length <= textLength
        else { return }

        let isOrdered = listItem.parent is OrderedList
        let markerRange = listMarkerRange(in: itemNS, ordered: isOrdered)

        if let checkbox = listItem.checkbox {
            // The checkbox glyph replaces the bullet/number entirely, so hide it
            // the same way heading/link delimiters are hidden elsewhere.
            if let markerRange {
                elements.append(StyledElement(
                    fullRange: markerRange, contentRange: markerRange,
                    delimiterRanges: [markerRange], attributes: [:]
                ))
            }
            if let bracketRange = checkboxBracketRange(in: itemNS) {
                let checked = checkbox == .checked
                checkboxes.append((range: bracketRange, checked: checked))
                elements.append(StyledElement(
                    fullRange: bracketRange,
                    contentRange: bracketRange,
                    delimiterRanges: [],
                    attributes: checked
                        ? MarkdownTheme.shared.checkboxCheckedAttributes
                        : MarkdownTheme.shared.checkboxUncheckedAttributes
                ))
                // Grey out the task's own text when checked, so a completed
                // task visibly recedes. Only the foreground color is set here
                // (no font), and it's appended before descending into the
                // item's inline content below, so nested styling (bold,
                // links, inline code) still applies its own attributes on
                // top rather than being overridden by this dimming.
                if checked {
                    let textStart = NSMaxRange(bracketRange)
                    let textRange = NSRange(location: textStart, length: NSMaxRange(itemNS) - textStart)
                    if textRange.length > 0 {
                        elements.append(StyledElement(
                            fullRange: textRange,
                            contentRange: textRange,
                            delimiterRanges: [],
                            attributes: MarkdownTheme.shared.checkedTaskTextAttributes
                        ))
                    }
                }
            }
            return
        }

        guard let markerRange else { return }
        elements.append(StyledElement(
            fullRange: markerRange, contentRange: markerRange,
            delimiterRanges: [],
            attributes: isOrdered
                ? MarkdownTheme.shared.listNumberAttributes
                : MarkdownTheme.shared.listBulletAttributes
        ))
    }

    /// Locates the bullet ("-"/"*"/"+") or ordered-number ("1." / "2)") marker
    /// at the start of a list item's source range.
    private func listMarkerRange(in itemRange: NSRange, ordered: Bool) -> NSRange? {
        let text = converter.fullString as NSString
        let searchLength = min(24, itemRange.length)
        guard searchLength > 0, itemRange.location + searchLength <= text.length else { return nil }
        let snippet = text.substring(with: NSRange(location: itemRange.location, length: searchLength))

        if ordered {
            var digitCount = 0
            for ch in snippet {
                if ch.isNumber { digitCount += 1 } else { break }
            }
            guard digitCount > 0 else { return nil }
            let delimIndex = snippet.index(snippet.startIndex, offsetBy: digitCount)
            guard delimIndex < snippet.endIndex, snippet[delimIndex] == "." || snippet[delimIndex] == ")" else { return nil }
            return NSRange(location: itemRange.location, length: digitCount + 1)
        } else {
            guard let first = snippet.first, first == "-" || first == "*" || first == "+" else { return nil }
            return NSRange(location: itemRange.location, length: 1)
        }
    }

    /// Locates the "[ ]"/"[x]"/"[X]" bracket within a list item's source range.
    /// The bracket always sits shortly after the bullet marker, so the search
    /// window only needs to cover marker + indentation, not the whole item.
    private func checkboxBracketRange(in itemRange: NSRange) -> NSRange? {
        let text = converter.fullString as NSString
        let searchLength = min(24, itemRange.length)
        guard searchLength > 0, itemRange.location + searchLength <= text.length else { return nil }
        let snippet = text.substring(with: NSRange(location: itemRange.location, length: searchLength))
        for pattern in ["[ ]", "[x]", "[X]"] {
            if let r = snippet.range(of: pattern) {
                let offset = snippet.distance(from: snippet.startIndex, to: r.lowerBound)
                return NSRange(location: itemRange.location + offset, length: 3)
            }
        }
        return nil
    }

    // MARK: - Block quotes

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let sourceRange = blockQuote.range,
              let nsRange = converter.nsRange(for: sourceRange),
              nsRange.location + nsRange.length <= textLength
        else {
            descendInto(blockQuote)
            return
        }

        // Style the whole block (no italics — just a muted color), and color
        // each line's "> " marker with the accent color used for links and
        // list bullets. Lines with no "> " of their own (CommonMark's "lazy
        // continuation": a line directly following a quoted line is still
        // part of the same blockquote even without a marker) simply keep the
        // block's own styling — nothing extra needed since there's no marker
        // to color and no custom drawing anywhere in this feature anymore.
        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: nsRange,
            delimiterRanges: [],
            attributes: MarkdownTheme.shared.blockQuoteAttributes
        ))
        for markerRange in blockQuoteMarkerRanges(in: nsRange) {
            elements.append(StyledElement(
                fullRange: markerRange,
                contentRange: markerRange,
                delimiterRanges: [],
                attributes: MarkdownTheme.shared.blockQuoteMarkerAttributes
            ))
        }
        descendInto(blockQuote)
    }

    /// Finds the "> " (or ">") prefix at the start of each line within a
    /// blockquote's source range, so it can be colored with the accent color.
    private func blockQuoteMarkerRanges(in blockRange: NSRange) -> [NSRange] {
        let text = converter.fullString as NSString
        let gt = UInt16(UnicodeScalar(">").value)
        let space = UInt16(UnicodeScalar(" ").value)
        var markers: [NSRange] = []
        var lineStart = blockRange.location
        let blockEnd = NSMaxRange(blockRange)

        while lineStart < blockEnd {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let lineEnd = min(NSMaxRange(lineRange), blockEnd)

            var cursor = lineRange.location
            while cursor < lineEnd, text.character(at: cursor) == space {
                cursor += 1
            }
            if cursor < lineEnd, text.character(at: cursor) == gt {
                var markerEnd = cursor + 1
                if markerEnd < lineEnd, text.character(at: markerEnd) == space {
                    markerEnd += 1
                }
                markers.append(NSRange(location: cursor, length: markerEnd - cursor))
            }

            guard NSMaxRange(lineRange) > lineStart else { break }
            lineStart = NSMaxRange(lineRange)
        }
        return markers
    }

    // MARK: - Tables

    mutating func visitTable(_ table: Table) {
        guard let sourceRange = table.range,
              let tableNS = converter.nsRange(for: sourceRange),
              tableNS.location + tableNS.length <= textLength
        else {
            descendInto(table)
            return
        }

        // Pipes and the separator row are always visible (never hidden as
        // delimiters) — collected here only so they can be colored with the
        // accent color, not to feed activeSpanRange/glyph-hiding.
        var pipeRanges: [NSRange] = []

        // Collect cell info for column width calculation.
        // visualWidth accounts for hidden inline delimiters (**, _, `, ~~, []())
        // so kern padding aligns the visible content, not the raw character count.
        struct CellInfo {
            let nsRange: NSRange
            let visualWidth: Int
            let isHeader: Bool
            let columnIndex: Int
        }
        var allCells: [CellInfo] = []
        // Separator row's own dash/colon runs. Kept in a separate array from
        // allCells only because they're not "isHeader" cells for the bold-
        // styling loop below — they still count toward column width (see
        // maxColumnWidths) and get kerned (see the padding loop) exactly
        // like real cells.
        var separatorCells: [CellInfo] = []

        let head = table.head
        if let headRange = head.range, let headNS = converter.nsRange(for: headRange) {
            collectPipeRanges(head, nsRange: headNS, into: &pipeRanges)

            for (colIdx, cell) in head.cells.enumerated() {
                if let cr = cell.range, let ns = converter.nsRange(for: cr),
                   ns.location + ns.length <= textLength {
                    let hidden = countHiddenDelimiters(in: cell)
                    allCells.append(CellInfo(nsRange: ns, visualWidth: max(0, ns.length - hidden),
                                             isHeader: true, columnIndex: colIdx))
                }
            }

            // Separator row (| --- | --- |): visible, colored as an accent row,
            // not hidden — exclude the trailing newline from the colored range.
            // head.range ends AT its own trailing "\n" (not past it), so +1 is
            // needed to land sepStart on the separator's own leading "|".
            let body = table.body
            if let bodyRange = body.range, let bodyNS = converter.nsRange(for: bodyRange) {
                let sepStart = NSMaxRange(headNS) + 1
                let sepEnd = bodyNS.location
                if sepEnd > sepStart + 1 {
                    let sepRange = NSRange(location: sepStart, length: sepEnd - sepStart - 1)
                    pipeRanges.append(sepRange)
                    for (colIdx, segment) in separatorColumnRanges(sepRange, in: converter.fullString).enumerated() {
                        separatorCells.append(CellInfo(nsRange: segment, visualWidth: segment.length,
                                                       isHeader: false, columnIndex: colIdx))
                    }
                }

                for row in body.rows {
                    if let rowRange = row.range, let rowNS = converter.nsRange(for: rowRange) {
                        collectPipeRanges(row, nsRange: rowNS, into: &pipeRanges)

                        for (colIdx, cell) in row.cells.enumerated() {
                            if let cr = cell.range, let ns = converter.nsRange(for: cr),
                               ns.location + ns.length <= textLength {
                                let hidden = countHiddenDelimiters(in: cell)
                                allCells.append(CellInfo(nsRange: ns, visualWidth: max(0, ns.length - hidden),
                                                         isHeader: false, columnIndex: colIdx))
                            }
                        }
                    }
                }
            }
        }

        // Calculate max visual column width. The separator's own dash/colon
        // runs count too — otherwise widening the separator past the real
        // cells' width doesn't pull the rest of the column along with it,
        // leaving the separator sticking out unaligned with everything else.
        var maxColumnWidths: [Int: Int] = [:]
        for cell in allCells + separatorCells {
            maxColumnWidths[cell.columnIndex] = max(
                maxColumnWidths[cell.columnIndex, default: 0], cell.visualWidth)
        }
        let columnCount = (maxColumnWidths.keys.max() ?? -1) + 1

        // Character advancement for monospace font
        let charWidth = MarkdownTheme.shared.codeFont.maximumAdvancement.width

        // 1. Whole table: monospace font. Pipes and the separator row stay
        // visible (no delimiterRanges) so table boundaries read at a glance.
        elements.append(StyledElement(
            fullRange: tableNS,
            contentRange: tableNS,
            delimiterRanges: [],
            attributes: MarkdownTheme.shared.tableAttributes
        ))

        // 1b. Pipes + separator row: colored with the accent, same as other
        // structural markers (blockquote ">", list bullets) that stay visible.
        for range in pipeRanges where range.length > 0 {
            elements.append(StyledElement(
                fullRange: range,
                contentRange: range,
                delimiterRanges: [],
                attributes: MarkdownTheme.shared.tablePipeAttributes
            ))
        }

        // 2. Header cells: bold monospace
        for cell in allCells where cell.isHeader {
            elements.append(StyledElement(
                fullRange: cell.nsRange,
                contentRange: cell.nsRange,
                delimiterRanges: [],
                attributes: MarkdownTheme.shared.tableHeaderAttributes
            ))
        }

        // 3. Column padding: kern on last character of each cell pads to max visual width.
        //    Also compensates for hidden inter-column pipes (1 charWidth each).
        //    Separator dash-runs are included so its pipes align with the rest of the table.
        for cell in allCells + separatorCells {
            let maxWidth = maxColumnWidths[cell.columnIndex, default: cell.visualWidth]
            let deficit = maxWidth - cell.visualWidth
            let isLastColumn = cell.columnIndex == columnCount - 1
            let extraChars = deficit + (isLastColumn ? 0 : 1)
            if extraChars > 0 && cell.nsRange.length > 0 {
                let lastCharRange = NSRange(location: NSMaxRange(cell.nsRange) - 1, length: 1)
                let kernValue = CGFloat(extraChars) * charWidth
                elements.append(StyledElement(
                    fullRange: lastCharRange,
                    contentRange: lastCharRange,
                    delimiterRanges: [],
                    attributes: [.kern: kernValue]
                ))
            }
        }

        // 4. Compute total table width for horizontal scrolling
        //    Sum of max column widths + inter-column pipe gaps + safety margin
        //    for leading/trailing pipes and font metric rounding
        let totalTableWidth = (0..<columnCount).reduce(CGFloat(0)) { sum, col in
            sum + CGFloat(maxColumnWidths[col, default: 0]) * charWidth
        } + CGFloat(max(0, columnCount - 1)) * charWidth + 2 * charWidth
        tableRegions.append((charRange: tableNS, requiredWidth: totalTableWidth))

        descendInto(table)
    }

    /// Collects pipe/gap ranges for a single table row (gaps between row bounds and cell ranges).
    private mutating func collectPipeRanges(_ row: Markup, nsRange rowNS: NSRange, into pipes: inout [NSRange]) {
        var cursor = rowNS.location
        for child in row.children {
            if let childRange = child.range,
               let childNS = converter.nsRange(for: childRange) {
                if childNS.location > cursor {
                    pipes.append(NSRange(location: cursor, length: childNS.location - cursor))
                }
                cursor = NSMaxRange(childNS)
            }
        }
        let rowEnd = NSMaxRange(rowNS)
        if rowEnd > cursor {
            pipes.append(NSRange(location: cursor, length: rowEnd - cursor))
        }
    }

    /// Splits a separator row range (e.g. "| --- | --- |") into per-column
    /// NSRanges — the raw span between each pair of pipes, padding spaces
    /// included. There's no AST cell structure for the separator, so this is
    /// done by scanning for "|" directly. Padding is deliberately kept
    /// in (not trimmed to the bare dashes) because real `Table.Cell.range`
    /// values include their own surrounding padding too — trimming only the
    /// separator's segments would compare its width on a different basis
    /// than real cells' visualWidth and throw off the deficit math.
    private func separatorColumnRanges(_ range: NSRange, in text: String) -> [NSRange] {
        let ns = text as NSString
        var result: [NSRange] = []
        var cursor = range.location
        let end = NSMaxRange(range)
        while cursor < end {
            let pipeLoc = ns.range(of: "|", range: NSRange(location: cursor, length: end - cursor)).location
            let segmentEnd = pipeLoc == NSNotFound ? end : pipeLoc
            if segmentEnd > cursor {
                result.append(NSRange(location: cursor, length: segmentEnd - cursor))
            }
            guard pipeLoc != NSNotFound else { break }
            cursor = pipeLoc + 1
        }
        return result
    }

    /// Counts characters within a node that will be hidden as inline delimiters.
    /// Used to compute visual cell width for table column alignment.
    private func countHiddenDelimiters(in node: Markup) -> Int {
        var count = 0
        for child in node.children {
            if child is Strong {
                count += 4  // ** + **
            } else if child is Emphasis {
                count += 2  // _ + _ or * + *
            } else if child is InlineCode {
                count += 2  // ` + `
            } else if child is Strikethrough {
                count += 4  // ~~ + ~~
            } else if let link = child as? Link {
                // [text](url) — delimiter chars = total range minus children ranges
                if let lr = link.range, let lns = converter.nsRange(for: lr) {
                    var textLen = 0
                    for linkChild in link.children {
                        if let cr = linkChild.range, let ns = converter.nsRange(for: cr) {
                            textLen += ns.length
                        }
                    }
                    count += lns.length - textLen
                }
            }
            count += countHiddenDelimiters(in: child)
        }
        return count
    }

    // MARK: - Strikethrough

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        guard let sourceRange = strikethrough.range,
              let nsRange = converter.nsRange(for: sourceRange),
              nsRange.length >= 2,
              nsRange.location + nsRange.length <= textLength
        else {
            descendInto(strikethrough)
            return
        }

        // GFM accepts both "~text~" and "~~text~~" — count the actual leading
        // tildes rather than assuming 2, or single-tilde text loses its first
        // and last real character to a delimiter range sized for "~~".
        let text = converter.fullString as NSString
        var delimLen = 0
        while delimLen < nsRange.length / 2,
              text.character(at: nsRange.location + delimLen) == Self.tildeUTF16 {
            delimLen += 1
        }
        guard delimLen > 0 else {
            descendInto(strikethrough)
            return
        }

        let openDelim = NSRange(location: nsRange.location, length: delimLen)
        let closeDelim = NSRange(location: NSMaxRange(nsRange) - delimLen, length: delimLen)
        let contentRange = NSRange(location: nsRange.location + delimLen, length: nsRange.length - delimLen * 2)

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: [openDelim, closeDelim],
            attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        ))
        descendInto(strikethrough)
    }

    private static let tildeUTF16 = UInt16(UnicodeScalar("~").value)
}

