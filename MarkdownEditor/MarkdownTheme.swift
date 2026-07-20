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

    /// Resolves the rounded-design variant of the system font, falling back to
    /// nil (callers substitute the plain system font) if unavailable.
    private static func roundedFont(
        size: CGFloat, weight: NSFont.Weight, traits: NSFontDescriptor.SymbolicTraits = []
    ) -> NSFont? {
        var descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        descriptor = descriptor.withDesign(.rounded) ?? descriptor
        if !traits.isEmpty {
            descriptor = descriptor.withSymbolicTraits(traits)
        }
        return NSFont(descriptor: descriptor, size: size)
    }

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
        // A rounded system design reads as noticeably warmer/friendlier than
        // plain SF Pro, at zero asset cost. The rounded design has no true
        // italic face, though — asking for rounded+italic together silently
        // resolves to a non-italic rounded font rather than failing, so
        // italic/bold-italic stick with the plain (non-rounded) system font,
        // which does have real italic glyphs.
        defaultFont = Self.roundedFont(size: baseSize, weight: .regular) ?? .systemFont(ofSize: baseSize)
        boldFont = Self.roundedFont(size: baseSize, weight: .bold) ?? .boldSystemFont(ofSize: baseSize)
        let italicDesc = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
            .withSymbolicTraits(.italic)
        italicFont = NSFont(descriptor: italicDesc, size: baseSize) ?? .systemFont(ofSize: baseSize)
        let boldItalicDesc = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
            .withSymbolicTraits([.bold, .italic])
        boldItalicFont = NSFont(descriptor: boldItalicDesc, size: baseSize) ?? .boldSystemFont(ofSize: baseSize)
        codeFont = .monospacedSystemFont(ofSize: baseSize - 1, weight: .regular)
        codeBoldFont = .monospacedSystemFont(ofSize: baseSize - 1, weight: .bold)

        headingFonts = headingSizes.map { size in
            Self.roundedFont(size: size, weight: .bold) ?? .systemFont(ofSize: size, weight: .bold)
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
        // A warm terracotta accent instead of system blue — this is what keeps
        // links and underlines from looking like default AppKit.
        linkColor = isDark
            ? NSColor(calibratedRed: 0.92, green: 0.58, blue: 0.50, alpha: 1)
            : NSColor(calibratedRed: 0.72, green: 0.36, blue: 0.30, alpha: 1)
        highlightColor = isDark
            ? NSColor(calibratedRed: 0.6, green: 0.55, blue: 0.1, alpha: 0.4)
            : NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.3, alpha: 0.5)
        blockQuoteColor = .secondaryLabelColor
        delimiterColor = .tertiaryLabelColor
        backgroundColor = isDark
            ? NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.17, alpha: 1)
            : NSColor(calibratedRed: 0.995, green: 0.99, blue: 0.965, alpha: 1)
        // Matches the accent used for links/bullets/quote bar.
        cursorColor = linkColor
        findMatchColor = isDark
            ? NSColor(calibratedRed: 0.6, green: 0.55, blue: 0.15, alpha: 0.45)
            : NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.0, alpha: 0.4)
        findCurrentMatchColor = isDark
            ? NSColor(calibratedRed: 0.9, green: 0.5, blue: 0.1, alpha: 0.7)
            : NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.0, alpha: 0.5)

        rebuildCachedAttributes()
    }

    private func rebuildCachedAttributes() {
        let paraStyle = defaultParagraphStyle
        defaultAttributes = [
            .font: defaultFont,
            .foregroundColor: defaultColor,
            .paragraphStyle: paraStyle,
        ]
        boldAttributes = [.font: boldFont]
        italicAttributes = [.font: italicFont]
        boldItalicAttributes = [.font: boldItalicFont]
        inlineCodeAttributes = [
            .font: codeFont,
            .foregroundColor: codeColor,
            .backgroundColor: codeBackgroundColor,
        ]
        codeBlockAttributes = [
            .font: codeFont,
            .foregroundColor: codeColor,
            .backgroundColor: codeBackgroundColor,
        ]
        linkAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let blockQuotePara = NSMutableParagraphStyle()
        blockQuotePara.lineSpacing = 3
        blockQuotePara.paragraphSpacing = 4
        blockQuoteAttributes = [
            .foregroundColor: blockQuoteColor,
            .paragraphStyle: blockQuotePara,
        ]
        // The literal ">" marker, colored with the same accent used for
        // links/bullets rather than hidden — no custom drawing involved.
        blockQuoteMarkerAttributes = [.foregroundColor: linkColor]
        tableAttributes = [.font: codeFont]
        tableHeaderAttributes = [.font: codeBoldFont]
        // Pipes and the separator row stay visible (never hidden) — colored
        // with the same accent as blockquote markers/links/bullets so table
        // structure reads at a glance without needing the cursor inside it.
        tablePipeAttributes = [.foregroundColor: linkColor]
        highlightAttributes = [.backgroundColor: highlightColor]
        // Unchecked boxes use the same accent as bullets/links so an open task
        // reads as a live list item; checked boxes (and their task text, set
        // below) dim to secondary-label grey — still legible, but visually
        // deprioritized now that the task is done.
        checkboxUncheckedAttributes = [.font: codeBoldFont, .foregroundColor: linkColor]
        checkboxCheckedAttributes = [.font: codeBoldFont, .foregroundColor: NSColor.secondaryLabelColor]
        checkedTaskTextAttributes = [.foregroundColor: NSColor.secondaryLabelColor]
        // The literal bullet marker ("-"/"*"/"+") stays on screen, just
        // recolored — same treatment as blockquote's ">" and table pipes,
        // rather than being replaced with a synthetic shape. It's real
        // source content (CommonMark treats a change of marker character as
        // starting a new list), so hiding or replacing it would discard
        // information the way hiding "**" doesn't.
        listBulletAttributes = [.foregroundColor: linkColor]
        listNumberAttributes = [.foregroundColor: linkColor]
        // Thematic breaks ("---"/"***"/"___") are the purest case of "the
        // whole line is the delimiter" — same accent treatment.
        thematicBreakAttributes = [.foregroundColor: linkColor]
        // Pre-compute heading attribute dicts for all 6 levels
        cachedHeadingAttributes = headingSizes.enumerated().map { (idx, _) -> [NSAttributedString.Key: Any] in
            let level = idx + 1
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
    }

    // MARK: - Cached attribute dictionaries (rebuilt on theme change)

    private(set) var defaultAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var boldAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var italicAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var boldItalicAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var inlineCodeAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var codeBlockAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var linkAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var blockQuoteAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var blockQuoteMarkerAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var tableAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var tableHeaderAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var tablePipeAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var thematicBreakAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var highlightAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var checkboxUncheckedAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var checkboxCheckedAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var checkedTaskTextAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var listBulletAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var listNumberAttributes: [NSAttributedString.Key: Any] = [:]
    private var cachedHeadingAttributes: [[NSAttributedString.Key: Any]] = []

    func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let idx = max(0, min(level - 1, cachedHeadingAttributes.count - 1))
        return cachedHeadingAttributes[idx]
    }

    /// A Setext heading's text line(s) and its own "==="/"---" underline are
    /// separate NSTextView paragraphs (paragraph boundaries follow "\n",
    /// regardless of shared markdown-node identity), but headingAttributes(level:)'s
    /// paragraphStyle carries both spacing-before-the-heading-block AND
    /// spacing-after-the-heading-block on a single style meant for one
    /// physical line. Applying that same style to every line double-counts:
    /// one line's own spacing-after plus the next line's spacing-before
    /// both add up between them, opening a gap that shouldn't be there.
    /// Zero spacing-after here unconditionally (no gap before whatever
    /// line follows within the heading — content line or underline).
    /// `isFirstLine` controls spacing-before: CommonMark allows a Setext
    /// heading's content to span more than one physical line ("one or more
    /// lines of text" before the underline) — only the very first one
    /// should carry the gap above the whole heading block; a second
    /// content line getting that too would open an unwanted gap between it
    /// and the line before it, inside what should read as one tight block.
    func headingSetextContentAttributes(level: Int, isFirstLine: Bool) -> [NSAttributedString.Key: Any] {
        var attrs = headingAttributes(level: level)
        if let para = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            para.paragraphSpacing = 0
            if !isFirstLine {
                para.paragraphSpacingBefore = 0
            }
            attrs[.paragraphStyle] = para
        }
        return attrs
    }

    /// The underline-line counterpart to headingSetextContentAttributes(level:) —
    /// zeroes spacing-before (already provided by the content line above it)
    /// but keeps the heading block's normal spacing-after (the gap before
    /// whatever follows). Also recolors to the accent color: unlike ATX's
    /// "#" (pure noise once font size signals the level), the underline is
    /// the only thing distinguishing an H1 from an H2 in Setext, so it stays
    /// visible rather than hidden. No .font override here — MarkdownStyleMap
    /// applies this after the content line's own attributes, so the
    /// underline keeps inheriting the heading font (and thus its size), and
    /// only color and paragraph spacing are overridden.
    func headingUnderlineAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: linkColor]
        if let para = (headingAttributes(level: level)[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            para.paragraphSpacingBefore = 0
            attrs[.paragraphStyle] = para
        }
        return attrs
    }

    private var defaultParagraphStyle: NSParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.paragraphSpacing = 4
        return para
    }
}
