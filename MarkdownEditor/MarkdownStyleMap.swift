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
    /// Character index → replacement glyph character, for reshaping unordered
    /// bullet markers ("-"/"*") into filled/hollow circles and diamonds by depth.
    private(set) var listMarkerGlyphOverrides: [(location: Int, character: Character)]

    init(text: String) {
        guard !text.isEmpty else {
            self.elements = []
            self.allDelimiterRanges = []
            self.tableRegions = []
            self.checkboxes = []
            self.headings = []
            self.listMarkerGlyphOverrides = []
            return
        }
        let doc = Document(parsing: text)
        let conv = SourceRangeConverter(text)
        let len = (text as NSString).length
        var walker = StyleWalker(converter: conv, textLength: len)
        walker.visit(doc)
        self.elements = walker.elements
        self.allDelimiterRanges = walker.elements.flatMap(\.delimiterRanges)
        self.tableRegions = walker.tableRegions
        self.checkboxes = walker.checkboxes
        self.headings = walker.headings
        self.listMarkerGlyphOverrides = walker.listMarkerGlyphOverrides
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
    var listMarkerGlyphOverrides: [(location: Int, character: Character)] = []
    var listDepth = 0

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
        if isATX {
            let delimiterLength = min(level + 1, nsRange.length) // "## " = level + space
            delimiterRange = NSRange(location: nsRange.location, length: delimiterLength)
            contentRange = NSRange(location: nsRange.location + delimiterLength,
                                   length: max(0, nsRange.length - delimiterLength))
        } else {
            // Setext heading: nsRange spans both the text line and its "===" /
            // "---" underline. Keep the text line visible; hide the underline.
            // When no blank line separates the heading from whatever follows,
            // swift-markdown's reported nsRange can extend past the underline
            // into that next block — clamp everything to the underline's own
            // line rather than trusting nsRange's upper bound, otherwise the
            // next paragraph gets swallowed into the heading's styling and
            // partially hidden as a "delimiter".
            let textLineRange = text.lineRange(for: NSRange(location: nsRange.location, length: 0))
            let contentEnd = min(NSMaxRange(textLineRange), NSMaxRange(nsRange))
            contentRange = NSRange(location: nsRange.location, length: contentEnd - nsRange.location)
            let underlineLineRange = text.lineRange(for: NSRange(location: contentEnd, length: 0))
            let delimiterEnd = min(NSMaxRange(underlineLineRange), NSMaxRange(nsRange))
            delimiterRange = NSRange(location: contentEnd, length: max(0, delimiterEnd - contentEnd))
            elementRange = NSRange(location: nsRange.location, length: delimiterEnd - nsRange.location)
        }

        elements.append(StyledElement(
            fullRange: elementRange,
            contentRange: contentRange,
            delimiterRanges: [delimiterRange],
            attributes: MarkdownTheme.shared.headingAttributes(level: level)
        ))
        headings.append((
            range: elementRange,
            level: level,
            title: heading.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        descendInto(heading)
    }

    private static let hashUTF16 = UInt16(UnicodeScalar("#").value)

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

        let openDelim = NSRange(location: nsRange.location, length: 2)
        let closeDelim = NSRange(location: NSMaxRange(nsRange) - 2, length: 2)
        let contentRange = NSRange(location: nsRange.location + 2, length: nsRange.length - 4)

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: [openDelim, closeDelim],
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

        let openDelim = NSRange(location: nsRange.location, length: 1)
        let closeDelim = NSRange(location: NSMaxRange(nsRange) - 1, length: 1)
        let contentRange = NSRange(location: nsRange.location + 1, length: nsRange.length - 2)

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: [openDelim, closeDelim],
            attributes: MarkdownTheme.shared.italicAttributes
        ))
        descendInto(emphasis)
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

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        listDepth += 1
        descendInto(unorderedList)
        listDepth -= 1
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        listDepth += 1
        descendInto(orderedList)
        listDepth -= 1
    }

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
        if !isOrdered {
            listMarkerGlyphOverrides.append((
                location: markerRange.location,
                character: Self.bulletCharacter(forDepth: max(1, listDepth))
            ))
        }
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

    /// Cycles unordered-bullet shape by nesting depth: filled circle, hollow
    /// circle, filled diamond, hollow diamond.
    private static func bulletCharacter(forDepth depth: Int) -> Character {
        switch depth {
        case 1: return "●"
        case 2: return "○"
        case 3: return "◆"
        default: return "◇"
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

        var delimiterRanges: [NSRange] = []

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

        let head = table.head
        if let headRange = head.range, let headNS = converter.nsRange(for: headRange) {
            collectPipeRanges(head, nsRange: headNS, into: &delimiterRanges)

            for (colIdx, cell) in head.cells.enumerated() {
                if let cr = cell.range, let ns = converter.nsRange(for: cr),
                   ns.location + ns.length <= textLength {
                    let hidden = countHiddenDelimiters(in: cell)
                    allCells.append(CellInfo(nsRange: ns, visualWidth: max(0, ns.length - hidden),
                                             isHeader: true, columnIndex: colIdx))
                }
            }

            // Separator row: hidden entirely except trailing newline
            let body = table.body
            if let bodyRange = body.range, let bodyNS = converter.nsRange(for: bodyRange) {
                let sepStart = NSMaxRange(headNS)
                let sepEnd = bodyNS.location
                if sepEnd > sepStart + 1 {
                    delimiterRanges.append(NSRange(location: sepStart, length: sepEnd - sepStart - 1))
                }

                for row in body.rows {
                    if let rowRange = row.range, let rowNS = converter.nsRange(for: rowRange) {
                        collectPipeRanges(row, nsRange: rowNS, into: &delimiterRanges)

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

        // Calculate max visual column width
        var maxColumnWidths: [Int: Int] = [:]
        for cell in allCells {
            maxColumnWidths[cell.columnIndex] = max(
                maxColumnWidths[cell.columnIndex, default: 0], cell.visualWidth)
        }
        let columnCount = (maxColumnWidths.keys.max() ?? -1) + 1

        // Character advancement for monospace font
        let charWidth = MarkdownTheme.shared.codeFont.maximumAdvancement.width

        // 1. Whole table: monospace font with pipes + separator hidden
        elements.append(StyledElement(
            fullRange: tableNS,
            contentRange: tableNS,
            delimiterRanges: delimiterRanges,
            attributes: MarkdownTheme.shared.tableAttributes
        ))

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
        for cell in allCells {
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

