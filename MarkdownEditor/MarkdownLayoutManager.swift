// MarkdownLayoutManager removed — the blockquote accent bar it drew was
// reverted in favor of coloring the literal ">" marker instead (see
// MarkdownStyleMap.visitBlockQuote and MarkdownTheme.blockQuoteMarkerAttributes).
// The custom drawBackground/drawGlyphs-based decoration kept surfacing new
// TextKit edge cases (reentrant layout queries, invalidation timing,
// CommonMark lazy-continuation lines) across several rounds of fixes, so it
// was simplified away rather than patched further.
