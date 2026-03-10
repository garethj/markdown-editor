import AppKit

final class MarkdownTheme {
    static let shared = MarkdownTheme()

    // MARK: - Fonts

    private(set) var defaultFont: NSFont
    private(set) var boldFont: NSFont
    private(set) var italicFont: NSFont
    private(set) var boldItalicFont: NSFont
    private(set) var codeFont: NSFont
    private(set) var codeBoldFont: NSFont
    private(set) var headingFonts: [NSFont] // index 0 = H1, etc.

    // MARK: - Colors

    private(set) var defaultColor: NSColor
    private(set) var headingColor: NSColor
    private(set) var codeColor: NSColor
    private(set) var codeBackgroundColor: NSColor
    private(set) var linkColor: NSColor
    private(set) var blockQuoteColor: NSColor
    private(set) var highlightColor: NSColor
    private(set) var delimiterColor: NSColor
    private(set) var backgroundColor: NSColor
    private(set) var cursorColor: NSColor
    private(set) var findMatchColor: NSColor
    private(set) var findCurrentMatchColor: NSColor

    // MARK: - Sizes

    private let baseSize: CGFloat = 15
    private let headingSizes: [CGFloat] = [28, 24, 20, 17, 15, 13]

    private init() {
        // Initialize with placeholder values; updateForCurrentAppearance fills real values
        defaultFont = .systemFont(ofSize: 15)
        boldFont = .boldSystemFont(ofSize: 15)
        italicFont = .systemFont(ofSize: 15)
        boldItalicFont = .systemFont(ofSize: 15)
        codeFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
        codeBoldFont = .monospacedSystemFont(ofSize: 14, weight: .bold)
        headingFonts = []
        defaultColor = .textColor
        headingColor = .textColor
        codeColor = .textColor
        codeBackgroundColor = .clear
        linkColor = .linkColor
        highlightColor = .yellow
        blockQuoteColor = .secondaryLabelColor
        delimiterColor = .tertiaryLabelColor
        backgroundColor = .textBackgroundColor
        cursorColor = .textColor
        findMatchColor = .yellow
        findCurrentMatchColor = .orange
        updateForCurrentAppearance()
    }

    func updateForCurrentAppearance() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Fonts
        defaultFont = .systemFont(ofSize: baseSize)
        boldFont = .boldSystemFont(ofSize: baseSize)
        let italicDesc = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
            .withSymbolicTraits(.italic)
        italicFont = NSFont(descriptor: italicDesc, size: baseSize) ?? .systemFont(ofSize: baseSize)

        let boldItalicDesc = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
            .withSymbolicTraits([.bold, .italic])
        boldItalicFont = NSFont(descriptor: boldItalicDesc, size: baseSize) ?? .boldSystemFont(ofSize: baseSize)
        codeFont = .monospacedSystemFont(ofSize: baseSize - 1, weight: .regular)
        codeBoldFont = .monospacedSystemFont(ofSize: baseSize - 1, weight: .bold)

        headingFonts = headingSizes.map { size in
            .systemFont(ofSize: size, weight: .bold)
        }

        // Colors
        defaultColor = .textColor
        headingColor = isDark
            ? NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
            : NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)
        codeColor = isDark
            ? NSColor(calibratedRed: 0.9, green: 0.55, blue: 0.5, alpha: 1)
            : NSColor(calibratedRed: 0.78, green: 0.24, blue: 0.24, alpha: 1)
        codeBackgroundColor = isDark
            ? NSColor(calibratedWhite: 1.0, alpha: 0.06)
            : NSColor(calibratedWhite: 0.0, alpha: 0.04)
        linkColor = .linkColor
        highlightColor = isDark
            ? NSColor(calibratedRed: 0.6, green: 0.55, blue: 0.1, alpha: 0.4)
            : NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.3, alpha: 0.5)
        blockQuoteColor = .secondaryLabelColor
        delimiterColor = .tertiaryLabelColor
        backgroundColor = isDark
            ? NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.17, alpha: 1)
            : NSColor(calibratedRed: 0.99, green: 0.99, blue: 0.98, alpha: 1)
        cursorColor = isDark
            ? .white
            : NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.25, alpha: 1)
        findMatchColor = isDark
            ? NSColor(calibratedRed: 0.6, green: 0.55, blue: 0.15, alpha: 0.45)
            : NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.0, alpha: 0.4)
        findCurrentMatchColor = isDark
            ? NSColor(calibratedRed: 0.9, green: 0.5, blue: 0.1, alpha: 0.7)
            : NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.0, alpha: 0.5)
    }

    // MARK: - Attribute dictionaries

    var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: defaultFont,
            .foregroundColor: defaultColor,
            .paragraphStyle: defaultParagraphStyle,
        ]
    }

    var boldAttributes: [NSAttributedString.Key: Any] {
        [.font: boldFont]
    }

    var italicAttributes: [NSAttributedString.Key: Any] {
        [.font: italicFont]
    }

    var boldItalicAttributes: [NSAttributedString.Key: Any] {
        [.font: boldItalicFont]
    }

    var inlineCodeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: codeColor,
            .backgroundColor: codeBackgroundColor,
        ]
    }

    var codeBlockAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: codeColor,
            .backgroundColor: codeBackgroundColor,
        ]
    }

    var linkAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
    }

    var blockQuoteAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: blockQuoteColor, .font: italicFont]
    }

    var tableAttributes: [NSAttributedString.Key: Any] {
        [.font: codeFont]
    }

    var tableHeaderAttributes: [NSAttributedString.Key: Any] {
        [.font: codeBoldFont]
    }

    var highlightAttributes: [NSAttributedString.Key: Any] {
        [.backgroundColor: highlightColor]
    }


    func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let idx = max(0, min(level - 1, headingFonts.count - 1))
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 4
        para.paragraphSpacingBefore = level <= 2 ? 12 : 8
        para.paragraphSpacing = level <= 2 ? 8 : 4
        return [
            .font: headingFonts[idx],
            .foregroundColor: headingColor,
            .paragraphStyle: para,
        ]
    }

    private var defaultParagraphStyle: NSParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.paragraphSpacing = 4
        return para
    }
}
