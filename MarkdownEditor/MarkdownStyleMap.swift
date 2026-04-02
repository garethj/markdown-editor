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

// MARK: - Table data for overlay rendering

struct TableData {
    struct Cell {
        let attributedText: NSAttributedString
        let isHeader: Bool
        let charRange: NSRange  // range in the backing store for cursor placement
    }
    let charRange: NSRange
    let requiredWidth: CGFloat
    let columnCount: Int
    let rows: [[Cell]]  // rows[rowIndex][colIndex]
    let maxColumnWidths: [CGFloat]  // natural width per column (in points, proportional font)
}

// MARK: - Style map

final class MarkdownStyleMap {
    private(set) var elements: [StyledElement]
    private(set) var allDelimiterRanges: [NSRange]
    /// Table regions with their required pixel width for horizontal scrolling.
    private(set) var tableRegions: [(charRange: NSRange, requiredWidth: CGFloat)]

    /// Structured table data for overlay rendering — built lazily on first access.
    private(set) lazy var tableData: [TableData] = {
        guard let document, let converter else { return [] }
        return Self.buildTableData(from: document, converter: converter, textLength: textLength)
    }()

    /// Stored AST and converter for lazy tableData building.
    private let document: Document?
    private let converter: SourceRangeConverter?
    private let textLength: Int

    init(text: String) {
        guard !text.isEmpty else {
            self.elements = []
            self.allDelimiterRanges = []
            self.tableRegions = []
            self.document = nil
            self.converter = nil
            self.textLength = 0
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
        self.document = doc
        self.converter = conv
        self.textLength = len
    }

    func appendElements(_ newElements: [StyledElement]) {
        elements.append(contentsOf: newElements)
        elements.sort { $0.fullRange.location < $1.fullRange.location }
        allDelimiterRanges.append(contentsOf: newElements.flatMap(\.delimiterRanges))
    }

    /// Walk only Table nodes in the AST to build TableData for overlay rendering.
    private static func buildTableData(from document: Document, converter: SourceRangeConverter, textLength: Int) -> [TableData] {
        var builder = TableDataBuilder(converter: converter, textLength: textLength)
        builder.visit(document)
        return builder.tableDataList
    }
}

// MARK: - AST walker

private struct StyleWalker: MarkupWalker {
    let converter: SourceRangeConverter
    let textLength: Int
    var elements: [StyledElement] = []
    var tableRegions: [(charRange: NSRange, requiredWidth: CGFloat)] = []

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

// MARK: - TableDataBuilder (lazy, only walks Table nodes)

private struct TableDataBuilder: MarkupWalker {
    let converter: SourceRangeConverter
    let textLength: Int
    var tableDataList: [TableData] = []

    mutating func visitTable(_ table: Table) {
        guard let sourceRange = table.range,
              let tableNS = converter.nsRange(for: sourceRange),
              tableNS.location + tableNS.length <= textLength
        else {
            descendInto(table)
            return
        }

        let head = table.head
        let charWidth = MarkdownTheme.shared.codeFont.maximumAdvancement.width

        // Determine column count from head cells
        let headCells = Array(head.cells)
        let columnCount = headCells.count

        // Compute totalTableWidth (mirrors StyleWalker logic for requiredWidth)
        var maxMonoWidths: [Int: Int] = [:]
        func countHidden(in node: Markup) -> Int {
            var c = 0
            for child in node.children {
                if child is Strong { c += 4 }
                else if child is Emphasis { c += 2 }
                else if child is InlineCode { c += 2 }
                else if child is Strikethrough { c += 4 }
                else if let link = child as? Link {
                    if let lr = link.range, let lns = converter.nsRange(for: lr) {
                        var textLen = 0
                        for lc in link.children {
                            if let cr = lc.range, let ns = converter.nsRange(for: cr) { textLen += ns.length }
                        }
                        c += lns.length - textLen
                    }
                }
                c += countHidden(in: child)
            }
            return c
        }
        for (colIdx, cell) in headCells.enumerated() {
            if let cr = cell.range, let ns = converter.nsRange(for: cr),
               ns.location + ns.length <= textLength {
                let hidden = countHidden(in: cell)
                maxMonoWidths[colIdx] = max(maxMonoWidths[colIdx, default: 0], max(0, ns.length - hidden))
            }
        }
        for row in table.body.rows {
            for (colIdx, cell) in row.cells.enumerated() {
                if let cr = cell.range, let ns = converter.nsRange(for: cr),
                   ns.location + ns.length <= textLength {
                    let hidden = countHidden(in: cell)
                    maxMonoWidths[colIdx] = max(maxMonoWidths[colIdx, default: 0], max(0, ns.length - hidden))
                }
            }
        }
        let totalTableWidth = (0..<columnCount).reduce(CGFloat(0)) { sum, col in
            sum + CGFloat(maxMonoWidths[col, default: 0]) * charWidth
        } + CGFloat(max(0, columnCount - 1)) * charWidth + 2 * charWidth

        // Build TableData with inline formatting
        let headerFont = MarkdownTheme.shared.tableOverlayHeaderFont
        let bodyFont = MarkdownTheme.shared.tableOverlayBodyFont

        var tableRows: [[TableData.Cell]] = []
        var propColumnWidths: [CGFloat] = Array(repeating: 0, count: columnCount)

        var headerRow: [TableData.Cell] = []
        for (colIdx, astCell) in head.cells.enumerated() {
            if let cr = astCell.range, let ns = converter.nsRange(for: cr),
               ns.location + ns.length <= textLength {
                let attrText = Self.buildCellAttributedString(from: astCell, baseFont: headerFont)
                headerRow.append(TableData.Cell(attributedText: attrText, isHeader: true, charRange: ns))
                if colIdx < columnCount {
                    propColumnWidths[colIdx] = max(propColumnWidths[colIdx], attrText.size().width + 24)
                }
            }
        }
        if !headerRow.isEmpty { tableRows.append(headerRow) }

        for row in table.body.rows {
            var bodyRow: [TableData.Cell] = []
            for (colIdx, astCell) in row.cells.enumerated() {
                if let cr = astCell.range, let ns = converter.nsRange(for: cr),
                   ns.location + ns.length <= textLength {
                    let attrText = Self.buildCellAttributedString(from: astCell, baseFont: bodyFont)
                    bodyRow.append(TableData.Cell(attributedText: attrText, isHeader: false, charRange: ns))
                    if colIdx < columnCount {
                        propColumnWidths[colIdx] = max(propColumnWidths[colIdx], attrText.size().width + 24)
                    }
                }
            }
            if !bodyRow.isEmpty { tableRows.append(bodyRow) }
        }

        tableDataList.append(TableData(
            charRange: tableNS,
            requiredWidth: totalTableWidth,
            columnCount: columnCount,
            rows: tableRows,
            maxColumnWidths: propColumnWidths
        ))

        // Don't descend — we've already processed all table children
    }

    // MARK: - Cell attributed string building

    private static func buildCellAttributedString(from cell: Table.Cell, baseFont: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let color = MarkdownTheme.shared.defaultColor
        for child in cell.children {
            appendInlineContent(child, to: result, font: baseFont, color: color)
        }
        let str = result.string
        let leading = str.prefix(while: { $0.isWhitespace }).count
        let trailing = str.reversed().prefix(while: { $0.isWhitespace }).count
        if leading > 0 || trailing > 0 {
            let len = max(0, result.length - leading - trailing)
            if len > 0 {
                return result.attributedSubstring(from: NSRange(location: leading, length: len))
            }
        }
        return result
    }

    private static func appendInlineContent(_ node: Markup, to result: NSMutableAttributedString, font: NSFont, color: NSColor) {
        let theme = MarkdownTheme.shared

        if let text = node as? Text {
            result.append(NSAttributedString(string: text.string, attributes: [.font: font, .foregroundColor: color]))
        } else if node is SoftBreak {
            result.append(NSAttributedString(string: " ", attributes: [.font: font, .foregroundColor: color]))
        } else if let strong = node as? Strong {
            let boldDesc = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.bold))
            let boldFont = NSFont(descriptor: boldDesc, size: font.pointSize) ?? font
            for child in strong.children {
                appendInlineContent(child, to: result, font: boldFont, color: color)
            }
        } else if let emphasis = node as? Emphasis {
            let italicDesc = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
            let italicFont = NSFont(descriptor: italicDesc, size: font.pointSize) ?? font
            for child in emphasis.children {
                appendInlineContent(child, to: result, font: italicFont, color: color)
            }
        } else if let code = node as? InlineCode {
            result.append(NSAttributedString(string: code.code, attributes: [
                .font: theme.codeFont,
                .foregroundColor: theme.codeColor,
                .backgroundColor: theme.codeBackgroundColor,
            ]))
        } else if let _ = node as? Strikethrough {
            let start = result.length
            for child in node.children {
                appendInlineContent(child, to: result, font: font, color: color)
            }
            if result.length > start {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                    range: NSRange(location: start, length: result.length - start))
            }
        } else if let _ = node as? Link {
            for child in node.children {
                appendInlineContent(child, to: result, font: font, color: theme.linkColor)
            }
        } else {
            for child in node.children {
                appendInlineContent(child, to: result, font: font, color: color)
            }
        }
    }
}
