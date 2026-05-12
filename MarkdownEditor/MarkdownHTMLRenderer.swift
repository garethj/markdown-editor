import Foundation
import Markdown

private let highlightRegex = try! NSRegularExpression(pattern: "==(.*?)==")
private let bareURLRegex = try! NSRegularExpression(
    pattern: #"https?://[^\s<>"'()\[\]]+"#)

// MARK: - HTML walker

private struct HTMLWalker: MarkupWalker {
    var result = ""
    let baseURL: URL?

    // MARK: Block elements

    mutating func visitHeading(_ heading: Heading) {
        let n = heading.level
        result += "<h\(n)>"
        descendInto(heading)
        result += "</h\(n)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        result += "<p>"
        descendInto(paragraph)
        result += "</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        result += "<blockquote>\n"
        descendInto(blockQuote)
        result += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let lang = codeBlock.language.map { " class=\"language-\(htmlEscape($0))\"" } ?? ""
        result += "<pre><code\(lang)>\(htmlEscape(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        result += html.rawHTML
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr>\n"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        result += "<ul>\n"
        descendInto(list)
        result += "</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        let startAttr = list.startIndex != 1 ? " start=\"\(list.startIndex)\"" : ""
        result += "<ol\(startAttr)>\n"
        descendInto(list)
        result += "</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let checkbox = listItem.checkbox {
            result += "<li class=\"task\">"
            result += "<input type=\"checkbox\" disabled"
            if checkbox == .checked { result += " checked" }
            result += ">"
            result += "<span class=\"task-body\">"
            descendInto(listItem)
            result += "</span>"
        } else {
            result += "<li>"
            descendInto(listItem)
        }
        result += "</li>\n"
    }

    mutating func visitTable(_ table: Table) {
        result += "<table>\n"
        descendInto(table)
        result += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        result += "<thead>\n<tr>\n"
        descendInto(tableHead)
        result += "</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        guard !tableBody.isEmpty else { return }
        result += "<tbody>\n"
        descendInto(tableBody)
        result += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        result += "<tr>\n"
        descendInto(tableRow)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        // The parent TableHead/TableBody context determines th vs td.
        // We inspect the parent chain to decide the element tag.
        let tag = tableCell.parent is Table.Head ? "th" : "td"
        result += "<\(tag)>"
        descendInto(tableCell)
        result += "</\(tag)>\n"
    }

    // MARK: Inline elements

    mutating func visitText(_ text: Text) {
        result += applyInlineMarkup(htmlEscape(text.string))
    }

    mutating func visitStrong(_ strong: Strong) {
        result += "<strong>"
        descendInto(strong)
        result += "</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        result += "<em>"
        descendInto(emphasis)
        result += "</em>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        result += "<del>"
        descendInto(strikethrough)
        result += "</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>\(htmlEscape(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Link) {
        let href = htmlEscape(link.destination ?? "")
        result += "<a href=\"\(href)\">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitImage(_ image: Image) {
        guard let src = image.source else { return }
        let resolved = resolveImageSource(src)
        let alt = htmlEscape(image.plainText)
        result += "<img src=\"\(resolved)\" alt=\"\(alt)\">\n"
    }

    mutating func visitInlineHTML(_ html: InlineHTML) {
        result += html.rawHTML
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        result += "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        result += "<br>\n"
    }

    // MARK: - Helpers

    private func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func applyInlineMarkup(_ escaped: String) -> String {
        var s = escaped
        let r1 = NSRange(s.startIndex..., in: s)
        s = highlightRegex.stringByReplacingMatches(
            in: s, range: r1, withTemplate: "<mark>$1</mark>")
        let r2 = NSRange(s.startIndex..., in: s)
        s = bareURLRegex.stringByReplacingMatches(
            in: s, range: r2, withTemplate: "<a href=\"$0\">$0</a>")
        return s
    }

    private func resolveImageSource(_ src: String) -> String {
        guard !src.hasPrefix("http://"), !src.hasPrefix("https://"),
              !src.hasPrefix("data:"), let baseURL else {
            return htmlEscape(src)
        }
        let url = baseURL.appendingPathComponent(src)
        guard let data = try? Data(contentsOf: url) else { return htmlEscape(src) }
        let mime: String
        switch url.pathExtension.lowercased() {
        case "png":          mime = "image/png"
        case "jpg", "jpeg":  mime = "image/jpeg"
        case "gif":          mime = "image/gif"
        case "svg":          mime = "image/svg+xml"
        case "webp":         mime = "image/webp"
        default:             mime = "image/png"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}

// MARK: - Public renderer

struct MarkdownHTMLRenderer {
    let baseURL: URL?

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    func fullDocument(markdown: String) -> String {
        let doc = Document(parsing: markdown)
        var walker = HTMLWalker(baseURL: baseURL)
        walker.visit(doc)
        return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="UTF-8">
            <style>
            \(Self.css)
            </style>
            </head>
            <body>
            \(walker.result)
            </body>
            </html>
            """
    }

    // MARK: - CSS

    private static let css = """
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, "SF Pro Text", system-ui, sans-serif;
            font-size: 15px;
            line-height: 1.65;
            color: #2c2c2e;
            max-width: 680px;
            margin: 0 auto;
            padding: 48px 0;
        }
        h1, h2, h3, h4, h5, h6 {
            font-weight: 700;
            color: #1c1c1e;
            line-height: 1.25;
            margin-top: 1.5em;
            margin-bottom: 0.4em;
            page-break-after: avoid;
        }
        h1 { font-size: 1.9em; margin-top: 0.5em; }
        h2 { font-size: 1.45em; }
        h3 { font-size: 1.2em; }
        h4 { font-size: 1.05em; }
        h5 { font-size: 1em; }
        h6 { font-size: 0.9em; color: #636366; }
        p { margin: 0 0 0.85em; }
        strong { font-weight: 700; }
        em { font-style: italic; }
        del { text-decoration: line-through; color: #8e8e93; }
        mark { background: #fff3b0; border-radius: 3px; padding: 1px 4px; }
        a { color: #0071e3; text-decoration: none; }
        code {
            font-family: "SF Mono", Menlo, Consolas, monospace;
            font-size: 0.875em;
            background: rgba(0,0,0,0.05);
            border-radius: 4px;
            padding: 1px 5px;
            color: #c0392b;
        }
        pre {
            background: #f5f5f7;
            border-radius: 8px;
            padding: 16px;
            overflow-x: auto;
            margin: 0 0 1em;
            page-break-inside: avoid;
        }
        pre code { background: none; padding: 0; color: #2c2c2e; font-size: 0.875em; }
        blockquote {
            border-left: 3px solid #d1d1d6;
            margin: 1em 0;
            padding: 0 1em;
            color: #636366;
        }
        blockquote p:last-child { margin-bottom: 0; }
        ul { padding-left: 1.75em; margin: 0 0 0.85em; }
        ol { padding-left: 2.5em; margin: 0 0 0.85em; }
        li { margin-bottom: 0.3em; }
        li > p { margin-bottom: 0.4em; }
        li > ul, li > ol { margin-top: 0.25em; margin-bottom: 0; }
        li.task {
            list-style: none;
            margin-left: -1.75em;
            padding-left: 1.75em;
            display: flex;
            gap: 0.5em;
            align-items: flex-start;
        }
        li.task > input[type="checkbox"] {
            margin-top: 0.28em;
            flex-shrink: 0;
        }
        li.task > .task-body { flex: 1; }
        li.task > .task-body > p { margin: 0; }
        hr { border: none; border-top: 1px solid #e5e5ea; margin: 2em 0; }
        img { max-width: 100%; height: auto; display: block; margin: 1em auto; }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 0 0 1em;
            font-size: 0.9em;
            page-break-inside: avoid;
        }
        th, td { border: 1px solid #e5e5ea; padding: 8px 12px; text-align: left; vertical-align: top; }
        th { background: #f5f5f7; font-weight: 600; color: #1c1c1e; }
        tr:nth-child(even) td { background: #fafafa; }
        @media print {
            body { max-width: none; padding: 0; margin: 0; }
        }
        """
}
