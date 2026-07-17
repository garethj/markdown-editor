import AppKit

/// Holds blockquote regions for the text view to read during its
/// `drawBackground(in:)` pass (see `EditorTextView`). The regions are stored
/// here rather than drawn here: querying layout (`glyphRange(forCharacterRange:)`,
/// `boundingRect(forGlyphRange:in:)`) from inside `NSLayoutManager.drawGlyphs`
/// is reentrant — it can trigger layout for other parts of the document while
/// layout is already in progress, and TextKit does not guarantee consistent
/// results when that happens. `drawBackground(in:)` runs as a distinct,
/// earlier phase of the same draw cycle (before glyphs are drawn), so the
/// same queries are safe to make there instead.
final class MarkdownLayoutManager: NSLayoutManager {
    var blockQuoteRegions: [NSRange] = []
}
