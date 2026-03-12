import AppKit

/// Custom text container that returns wider line-fragment rects for table lines,
/// allowing horizontal scrolling for wide tables while normal prose wraps at view width.
final class MarkdownTextContainer: NSTextContainer {

    /// Sorted by charRange.location. Updated from MarkdownTextStorage after styling.
    var tableLineRanges: [(charRange: NSRange, requiredWidth: CGFloat)] = [] {
        didSet { updateContainerWidth() }
    }

    /// The width at which normal (non-table) prose should wrap (matches clip view width).
    var proseWidth: CGFloat = 0 {
        didSet { updateContainerWidth() }
    }

    override func lineFragmentRect(
        forProposedRect proposedRect: NSRect,
        at characterIndex: Int,
        writingDirection baseWritingDirection: NSWritingDirection,
        remaining remainingRect: UnsafeMutablePointer<NSRect>?
    ) -> NSRect {
        var rect = super.lineFragmentRect(
            forProposedRect: proposedRect,
            at: characterIndex,
            writingDirection: baseWritingDirection,
            remaining: remainingRect
        )

        if let tableWidth = tableWidth(for: characterIndex) {
            // Table line — use table width if wider than the rect
            if tableWidth > rect.width {
                rect.size.width = tableWidth
            }
        } else if proseWidth > 0 && rect.width > proseWidth {
            // Non-table line — constrain to prose width so text wraps at window edge
            rect.size.width = proseWidth
        }

        return rect
    }

    /// Sets the container's size.width to max(proseWidth, widest table).
    /// This ensures the text view grows wide enough for table content.
    private func updateContainerWidth() {
        let maxTableWidth = tableLineRanges.map(\.requiredWidth).max() ?? 0
        let needed = max(proseWidth, maxTableWidth)
        if needed > 0 && abs(size.width - needed) > 1 {
            size = NSSize(width: needed, height: size.height)
            // Container size change requires explicit layout invalidation
            if let lm = layoutManager, lm.numberOfGlyphs > 0 {
                let fullRange = NSRange(location: 0, length: lm.numberOfGlyphs)
                lm.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            }
        }
    }

    /// Binary search for the required width of a table range containing the given character index.
    private func tableWidth(for characterIndex: Int) -> CGFloat? {
        var lo = 0
        var hi = tableLineRanges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = tableLineRanges[mid]
            if characterIndex < entry.charRange.location {
                hi = mid - 1
            } else if characterIndex >= NSMaxRange(entry.charRange) {
                lo = mid + 1
            } else {
                return entry.requiredWidth
            }
        }
        return nil
    }
}
