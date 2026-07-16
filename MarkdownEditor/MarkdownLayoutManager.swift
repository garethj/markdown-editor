import AppKit

/// Draws extra decoration alongside normal text glyphs — a colored accent
/// bar for blockquote paragraphs, and a custom checkbox glyph — without
/// needing per-element NSViews. This runs during the existing TextKit draw
/// pass, bounded to whatever glyph range is actually being redrawn, so cost
/// scales with what's on screen, not with document size.
final class MarkdownLayoutManager: NSLayoutManager {
    var blockQuoteRegions: [NSRange] = []

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawBlockQuoteBars(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawBlockQuoteBars(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard !blockQuoteRegions.isEmpty, textContainers.first != nil else { return }
        let barColor = MarkdownTheme.shared.linkColor
        let barWidth: CGFloat = 3
        let barOffsetFromText: CGFloat = 12

        for charRange in blockQuoteRegions {
            let quoteGlyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            guard NSIntersectionRange(quoteGlyphRange, glyphsToShow).length > 0 else { continue }

            enumerateLineFragments(forGlyphRange: quoteGlyphRange) { [self] _, usedRect, _, lineGlyphRange, _ in
                guard NSIntersectionRange(lineGlyphRange, glyphsToShow).length > 0 else { return }
                var barRect = usedRect
                barRect.origin.x += origin.x - barOffsetFromText
                barRect.origin.y += origin.y
                barRect.size.width = barWidth
                barColor.setFill()
                NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
        }
    }
}
