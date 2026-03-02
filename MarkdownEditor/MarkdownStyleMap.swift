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
