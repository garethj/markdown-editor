import AppKit

/// Draws extra decoration alongside normal text glyphs — a colored accent
/// bar for blockquote paragraphs, and a custom checkbox glyph — without
/// needing per-element NSViews. This runs during the existing TextKit draw
/// pass, bounded to whatever glyph range is actually being redrawn, so cost
/// scales with what's on screen, not with document size.
final class MarkdownLayoutManager: NSLayoutManager {
    var blockQuoteRegions: [NSRange] = []
    var checkboxRegions: [(range: NSRange, checked: Bool)] = []

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawBlockQuoteBars(forGlyphRange: glyphsToShow, at: origin)
        drawCheckboxes(forGlyphRange: glyphsToShow, at: origin)
    }

    /// The literal "[ ]"/"[x]" text is laid out but invisible (see
    /// `MarkdownTheme.checkboxTextAttributes`), reserving exactly its natural
    /// width; we draw an actual rounded checkbox in that reserved rect.
    private func drawCheckboxes(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard !checkboxRegions.isEmpty, let container = textContainers.first else { return }

        for checkbox in checkboxRegions {
            let glyphRange = self.glyphRange(forCharacterRange: checkbox.range, actualCharacterRange: nil)
            guard NSIntersectionRange(glyphRange, glyphsToShow).length > 0 else { continue }

            var rect = boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            drawCheckbox(in: rect, checked: checkbox.checked)
        }
    }

    private func drawCheckbox(in rect: NSRect, checked: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let size = min(rect.width, rect.height, 16)
        let boxRect = NSRect(
            x: rect.minX + (rect.width - size) / 2,
            y: rect.minY + (rect.height - size) / 2,
            width: size,
            height: size
        )
        let path = NSBezierPath(roundedRect: boxRect, xRadius: 4, yRadius: 4)

        if checked {
            MarkdownTheme.shared.checkboxCheckedColor.setFill()
            path.fill()

            let check = NSBezierPath()
            check.lineWidth = max(1.4, size * 0.11)
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: boxRect.minX + size * 0.24, y: boxRect.minY + size * 0.52))
            check.line(to: NSPoint(x: boxRect.minX + size * 0.42, y: boxRect.minY + size * 0.30))
            check.line(to: NSPoint(x: boxRect.minX + size * 0.78, y: boxRect.minY + size * 0.70))
            NSColor.white.setStroke()
            check.stroke()
        } else {
            path.lineWidth = 1.4
            MarkdownTheme.shared.delimiterColor.setStroke()
            path.stroke()
        }
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
