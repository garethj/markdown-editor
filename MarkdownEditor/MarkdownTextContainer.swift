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
        didSet {
            let widthChanged = updateContainerWidth()
            // Always invalidate layout when proseWidth changes, even if container
            // width didn't change (e.g. a wide table dominates container width but
            // prose lines still need to re-wrap at the new proseWidth).
            if !widthChanged && abs(proseWidth - oldValue) > 1 {
                invalidateEntireLayout()
            }
        }
    }

    /// Keeps table line ranges aligned with the text after an edit whose
    /// restyle has been deferred (see `MarkdownTextStorage.processEditing`),
    /// so wide line fragments stay on the table's own lines in the meantime.
    /// Deliberately does not touch `requiredWidth` — column widths only get
    /// recomputed by a real parse, and re-running `updateContainerWidth` here
    /// would churn the container size mid-burst.
    func adjustTableLineRangesForEdit(at location: Int, delta: Int) {
        guard delta != 0, !tableLineRanges.isEmpty else { return }
        // Built whole and assigned once: tableLineRanges has a didSet, and
        // mutating elements in place through the subscript would re-run it
        // for every entry.
        tableLineRanges = tableLineRanges.map { entry in
            var range = entry.charRange
            if range.location >= location {
                range.location = max(0, range.location + delta)
            } else if location < NSMaxRange(range) {
                range.length = max(0, range.length + delta)
            }
            return (charRange: range, requiredWidth: entry.requiredWidth)
        }
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
    /// Returns whether the width actually changed.
    @discardableResult
    private func updateContainerWidth() -> Bool {
        // lazy.map so re-assigning tableLineRanges — which happens on every
        // keystroke — doesn't allocate an intermediate array just to take a max.
        let maxTableWidth = tableLineRanges.lazy.map(\.requiredWidth).max() ?? 0
        let needed = max(proseWidth, maxTableWidth)
        guard needed > 0 && abs(size.width - needed) > 1 else { return false }
        size = NSSize(width: needed, height: size.height)
        // Container size change requires explicit layout invalidation
        invalidateEntireLayout()
        return true
    }

    /// Marks the whole document's layout invalid, which a width change really
    /// does require — every line has to re-wrap.
    ///
    /// Scoped by the text storage's length, deliberately not by
    /// `layoutManager.numberOfGlyphs`: reading that forces glyph generation
    /// for the entire document, defeating TextKit's lazy layout and costing
    /// real time on a long one. It was also the wrong unit — a glyph count
    /// passed to a method that wants a character range, which hidden
    /// delimiters make diverge. `invalidateLayout(forCharacterRange:)` only
    /// marks the range dirty, so layout stays lazy from here on.
    private func invalidateEntireLayout() {
        guard let lm = layoutManager, let length = lm.textStorage?.length, length > 0 else { return }
        lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: length),
                            actualCharacterRange: nil)
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
