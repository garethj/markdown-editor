import AppKit
import Markdown

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
    private let lineStartUTF8Offsets: [Int] // UTF-8 byte offset of each line start

    init(_ string: String) {
        self.string = string
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
    let elements: [StyledElement]
    let allDelimiterRanges: [NSRange]

    init(text: String) {
        guard !text.isEmpty else {
            self.elements = []
            self.allDelimiterRanges = []
            return
        }
        let document = Document(parsing: text)
        let converter = SourceRangeConverter(text)
        var walker = StyleWalker(converter: converter, textLength: (text as NSString).length)
        walker.visit(document)
        self.elements = walker.elements
        self.allDelimiterRanges = walker.elements.flatMap(\.delimiterRanges)
    }
}

// MARK: - AST walker

private struct StyleWalker: MarkupWalker {
    let converter: SourceRangeConverter
    let textLength: Int
    var elements: [StyledElement] = []

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
        let delimiterLength = level + 1 // "## " = level + space
        let delimLen = min(delimiterLength, nsRange.length)

        let delimiterRange = NSRange(location: nsRange.location, length: delimLen)
        let contentRange = NSRange(location: nsRange.location + delimLen,
                                   length: max(0, nsRange.length - delimLen))

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: [delimiterRange],
            attributes: MarkdownTheme.shared.headingAttributes(level: level)
        ))
        descendInto(heading)
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

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: [openBracket, closeDelim],
            attributes: MarkdownTheme.shared.linkAttributes
        ))
        descendInto(link)
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

        // Style the whole block; the ">" characters on each line are delimiters
        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: nsRange,
            delimiterRanges: [],
            attributes: MarkdownTheme.shared.blockQuoteAttributes
        ))
        descendInto(blockQuote)
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
              nsRange.length >= 4,
              nsRange.location + nsRange.length <= textLength
        else {
            descendInto(strikethrough)
            return
        }

        let openDelim = NSRange(location: nsRange.location, length: 2)
        let closeDelim = NSRange(location: NSMaxRange(nsRange) - 2, length: 2)
        let contentRange = NSRange(location: nsRange.location + 2, length: nsRange.length - 4)

        elements.append(StyledElement(
            fullRange: nsRange,
            contentRange: contentRange,
            delimiterRanges: [openDelim, closeDelim],
            attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        ))
        descendInto(strikethrough)
    }
}
