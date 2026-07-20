import AppKit

final class MarkdownTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    private(set) var lastStyleMap: MarkdownStyleMap?

    // MARK: - NSTextStorage required overrides

    override var string: String {
        backingStore.string
    }

    // NSAttributedString.attributes(at:effectiveRange:) throws (crashes) for
    // an out-of-bounds location, and callers of this override are AppKit's
    // own TextKit internals, not our code — we don't control every timing
    // window in which NSLayoutManager might ask. Confirmed happening for
    // real: selecting all text (including a table) and deleting it, then
    // immediately double-clicking the title bar to trigger an animated
    // window-zoom resize, crashed here — an in-flight CVDisplayLink-driven
    // redraw asked for attributes at an index that stopped being valid the
    // moment the delete landed, from a call stack with nothing to do with
    // our own edit/invalidation code (NSMoveHelper's animation timer racing
    // the edit). The real fixes are proper invalidation on that edit path
    // (see pendingDisplayInvalidationRange) — this guard is a last-resort
    // backstop so a similar race degrades to empty attributes instead of
    // taking the whole app down.
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        guard location >= 0, location < backingStore.length else {
            range?.pointee = NSRange(location: max(0, min(location, backingStore.length)), length: 0)
            return [:]
        }
        return backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()

        // Must run after endEditing() has fully returned, not just after
        // super.processEditing() inside it — processEditing() itself still
        // executes *inside* endEditing()'s call frame, so the text storage
        // is still in its "editing" state at that point. Calling
        // invalidateDisplay(forCharacterRange:) (or anything else that
        // triggers glyph generation) while still editing throws
        // NSInternalInconsistencyException ("attempted glyph generation
        // while textStorage is editing") — confirmed by hitting that
        // assertion directly while chasing the string-index-out-of-bounds
        // crash this replaced (see the comment on pendingDisplayInvalidationRange).
        if let range = pendingDisplayInvalidationRange {
            pendingDisplayInvalidationRange = nil
            for lm in layoutManagers {
                // invalidateLayout must run before invalidateDisplay, not
                // just alongside it. All the attribute writes in
                // applyMarkdownStyling go straight to backingStore (see the
                // comment above), so NSLayoutManager never got the normal
                // edited()-driven notification that anything in `range`
                // changed — its cached line fragment geometry can still
                // reflect the *old* font. If a character elsewhere in
                // `range` just grew into a heading font (e.g. finishing a
                // Setext heading by typing its "===" underline, which
                // changes the *text line above* the actual edit),
                // invalidateDisplay alone only marks a redraw using
                // whatever rect is currently cached — still the old,
                // shorter line height — so the taller glyph's top gets
                // clipped by that stale dirty rect on screen.
                // invalidateLayout forces the geometry to be recomputed
                // first, so the subsequent invalidateDisplay call marks the
                // *correct*, already-regrown rect.
                lm.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                lm.invalidateDisplay(forCharacterRange: range)
            }
        }
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Styling

    /// Tracks the edited range during processEditing for incremental styling.
    private var pendingEditedRange: NSRange?

    /// The range applyMarkdownStyling() wants redisplayed, consumed in
    /// replaceCharacters(in:with:) after endEditing() fully returns — see
    /// the comment there for why it can't happen any earlier.
    private var pendingDisplayInvalidationRange: NSRange?

    override func processEditing() {
        if editedMask.contains(.editedCharacters) {
            pendingEditedRange = editedRange
            applyMarkdownStyling()
            pendingEditedRange = nil
        }
        super.processEditing()
    }

    func applyMarkdownStyling() {
        let text = string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else {
            lastStyleMap = nil
            for lm in layoutManagers {
                (lm.delegate as? MarkdownLayoutManagerDelegate)?.updateDelimiters(from: nil)
                // Regression: this used to be skipped here, unlike the
                // non-empty path below — leaving tableLineRanges pointing at
                // character ranges from whatever document existed a moment
                // ago. MarkdownTextContainer.lineFragmentRect(forProposedRect:at:...)
                // binary-searches that array by character index on every
                // layout pass, including ones triggered by something
                // completely unrelated to us (e.g. an animated window-zoom
                // redraw) — a real crash was confirmed selecting all text in
                // a document containing a table, deleting it, then
                // double-clicking the title bar to zoom the window.
                if let container = lm.textContainers.first as? MarkdownTextContainer {
                    container.tableLineRanges = []
                }
            }
            // Also skipped here before, unlike every other edit (see
            // replaceCharacters) — going to empty relied entirely on the
            // standard edited()-driven glyph invalidation from
            // super.processEditing(). A zero-length range still gets
            // NSLayoutManager to reconcile its cached layout/glyph state
            // against the now-empty backingStore before anything else
            // (e.g. that same animated window-zoom redraw) tries to draw
            // against stale internal indices.
            pendingDisplayInvalidationRange = NSRange(location: 0, length: 0)
            return
        }

        // Determine the dirty region: expand editedRange to enclosing paragraph boundaries,
        // then one line further in each direction. Multi-line constructs like Setext
        // headings ("Text\n---") depend on a line other than the one actually edited —
        // e.g. deleting the "---" underline must also reset the heading font on the text
        // line above it, which a same-line-only dirty range would leave stale.
        let nsText = text as NSString
        let dirtyRange: NSRange
        if let edited = pendingEditedRange, edited.location != NSNotFound {
            var parStart = nsText.lineRange(for: NSRange(location: edited.location, length: 0)).location
            let editEnd = min(NSMaxRange(edited), nsText.length)
            var parEnd = NSMaxRange(nsText.lineRange(for: NSRange(location: max(0, editEnd > 0 ? editEnd - 1 : 0), length: 0)))
            if parStart > 0 {
                parStart = nsText.lineRange(for: NSRange(location: parStart - 1, length: 0)).location
            }
            if parEnd < nsText.length {
                parEnd = NSMaxRange(nsText.lineRange(for: NSRange(location: parEnd, length: 0)))
            }
            dirtyRange = NSRange(location: parStart, length: parEnd - parStart)
        } else {
            dirtyRange = fullRange
        }
        let isFullRestyle = NSEqualRanges(dirtyRange, fullRange)

        // Parse markdown (full AST required — cmark doesn't support incremental)
        let styleMap = MarkdownStyleMap(text: text)
        lastStyleMap = styleMap

        // Widen the dirty region to cover the full range of any element that
        // merely intersects it. This matters for compound styling — e.g. a
        // blockquote's own wide "whole block" element plus one small colored
        // "> " marker element per line: if only the edited line's own narrow
        // slice were used, editing one line would re-touch the wide element
        // (which intersects) while a marker element on a *different* line of
        // the same block wouldn't (its own tiny range doesn't intersect the
        // narrow dirty region) — so the wide element's re-application would
        // silently overwrite that marker's color with no chance for it to
        // reassert itself. Widening ensures every sub-element sharing space
        // with anything already being restyled gets restyled too.
        var effectiveDirtyRange = dirtyRange
        if !isFullRestyle {
            for element in styleMap.elements {
                guard element.fullRange.location + element.fullRange.length <= fullRange.length else { continue }
                if NSIntersectionRange(element.fullRange, dirtyRange).length > 0 {
                    effectiveDirtyRange = NSUnionRange(effectiveDirtyRange, element.fullRange)
                }
            }
        }

        // Reset attributes only on the (possibly widened) dirty region
        backingStore.setAttributes(MarkdownTheme.shared.defaultAttributes, range: effectiveDirtyRange)

        // Apply styles: scope to dirty region for incremental, all for full restyle
        for element in styleMap.elements {
            guard element.fullRange.location + element.fullRange.length <= fullRange.length else { continue }
            if isFullRestyle || NSIntersectionRange(element.fullRange, effectiveDirtyRange).length > 0 {
                applyAttributesMergingFontTraits(element.attributes, range: element.fullRange)
            }
        }

        // Style bare URLs and highlights scoped to dirty region
        applyBareURLStyling(text: text, fullRange: effectiveDirtyRange)

        let highlightElements = applyHighlightStyling(text: text, fullRange: effectiveDirtyRange, headingRanges: styleMap.headings.map { $0.range })
        if !highlightElements.isEmpty {
            styleMap.appendElements(highlightElements)
        }

        // Update delimiter ranges on layout delegates BEFORE glyph generation.
        for lm in layoutManagers {
            (lm.delegate as? MarkdownLayoutManagerDelegate)?.updateDelimiters(from: styleMap)
            if let container = lm.textContainers.first as? MarkdownTextContainer {
                container.tableLineRanges = styleMap.tableRegions
            }
        }

        // All the attribute writes above went straight to backingStore, not through
        // self.setAttributes — so nothing has told the layout manager anything in
        // effectiveDirtyRange actually changed. That's invisible for the exact
        // character range the user just typed in (NSTextView already redraws that from
        // the .editedCharacters edit that triggered this method), but any OTHER part of
        // effectiveDirtyRange the widening step pulled in (e.g. other rows' table-column
        // kerning, recomputed because one cell's width changed) would otherwise sit
        // correctly-styled-but-undisplayed until some unrelated event (cursor leaving the
        // table) forces a redraw there.
        //
        // A prior version of this fix called `self.edited(.editedAttributes, range:
        // effectiveDirtyRange, changeInLength: 0)` here — technically the idiomatic way to
        // extend an edit from inside processEditing, but it's *also* the exact channel
        // NSTextView listens on to sync its selection after an edit, and it left NSTextView
        // believing effectiveDirtyRange (i.e. the whole table) was *selected*, not just
        // edited. That's worse than a cursor jump: the next keystroke typed a replacement
        // for that "selection", deleting the rest of the table — confirmed via a UI test
        // that types multiple characters in a row after positioning the cursor in a cell
        // (TableCellFormattingUITests.testTypingInsideTableCellDoesNotMoveCursorPastTable;
        // a single-keystroke version of that test didn't catch it, since the first
        // keystroke alone still landed correctly). invalidateDisplay(forCharacterRange:)
        // forces the redraw without going through that edit-notification/selection-sync
        // path at all.
        //
        // The actual invalidateDisplay(forCharacterRange:) call happens in
        // processEditing(), after super.processEditing() — see the comment
        // there. Calling it directly from here would run it before layout
        // managers have been notified of this edit's length change.
        pendingDisplayInvalidationRange = effectiveDirtyRange
    }

    // MARK: - Bare URL detection

    private static let bareURLRegex: NSRegularExpression = {
        // Match http:// or https:// URLs not already inside markdown link syntax
        try! NSRegularExpression(
            pattern: #"https?://[^\s\)\]>]+"#,
            options: []
        )
    }()

    private func applyBareURLStyling(text: String, fullRange: NSRange) {
        let nsText = text as NSString
        let matches = Self.bareURLRegex.matches(in: text, options: [], range: fullRange)
        let linkAttrs = MarkdownTheme.shared.linkAttributes

        for match in matches {
            let range = match.range
            // Skip if this range already has a markdownLinkURL (i.e. it's inside a markdown link)
            if backingStore.attribute(.markdownLinkURL, at: range.location, effectiveRange: nil) != nil {
                continue
            }
            let urlString = nsText.substring(with: range)
            var attrs = linkAttrs
            attrs[.markdownLinkURL] = urlString
            backingStore.addAttributes(attrs, range: range)
        }
    }

    // MARK: - Highlight detection

    private static let highlightRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"==(.+?)=="#, options: [])
    }()

    private func applyHighlightStyling(text: String, fullRange: NSRange, headingRanges: [NSRange]) -> [StyledElement] {
        let matches = Self.highlightRegex.matches(in: text, options: [], range: fullRange)
        let highlightAttrs = MarkdownTheme.shared.highlightAttributes
        var elements: [StyledElement] = []

        for match in matches {
            let range = match.range
            guard range.length >= 5 else { continue } // ==x== minimum
            // A Setext heading's "===" underline is a run of literal "="
            // characters, which the "==(.+?)==" pattern above happily
            // matches purely by coincidence — it's structural syntax, not
            // `==highlighted text==`. Previously harmless (the underline's
            // glyphs were hidden, so a highlight background behind them was
            // invisible); now that the underline stays visible, a false
            // match there paints stray yellow blocks across it. Skip any
            // match that falls inside a heading's own range entirely.
            guard !headingRanges.contains(where: { NSIntersectionRange($0, range).length == range.length }) else { continue }

            let contentRange = NSRange(location: range.location + 2, length: range.length - 4)
            backingStore.addAttributes(highlightAttrs, range: contentRange)

            let openDelim = NSRange(location: range.location, length: 2)
            let closeDelim = NSRange(location: NSMaxRange(range) - 2, length: 2)

            elements.append(StyledElement(
                fullRange: range,
                contentRange: contentRange,
                delimiterRanges: [openDelim, closeDelim],
                attributes: highlightAttrs
            ))
        }
        return elements
    }

    // MARK: - Font trait merging

    /// Applies attributes to a range, merging font symbolic traits with any
    /// existing font so that nested formatting (bold inside italic, etc.) works.
    private func applyAttributesMergingFontTraits(_ attrs: [NSAttributedString.Key: Any], range: NSRange) {
        guard let incomingFont = attrs[.font] as? NSFont else {
            backingStore.addAttributes(attrs, range: range)
            return
        }

        // Apply all non-font attributes normally
        var nonFontAttrs = attrs
        nonFontAttrs.removeValue(forKey: .font)
        if !nonFontAttrs.isEmpty {
            backingStore.addAttributes(nonFontAttrs, range: range)
        }

        // Merge font traits with whatever font already exists at each sub-range
        backingStore.enumerateAttribute(.font, in: range, options: []) { existingValue, subRange, _ in
            let merged: NSFont
            if let existingFont = existingValue as? NSFont {
                merged = Self.mergeFontTraits(existing: existingFont, incoming: incomingFont)
            } else {
                merged = incomingFont
            }
            backingStore.addAttribute(.font, value: merged, range: subRange)
        }
    }

    /// Merges symbolic traits from two fonts. Monospace wins over system family
    /// but inherits bold/italic. Non-default size (heading sizes) wins.
    private static func mergeFontTraits(existing: NSFont, incoming: NSFont) -> NSFont {
        let existingTraits = existing.fontDescriptor.symbolicTraits
        let incomingTraits = incoming.fontDescriptor.symbolicTraits
        let unionTraits = existingTraits.union(incomingTraits)

        // Determine base font: monospace wins over system
        let existingMono = existingTraits.contains(.monoSpace)
        let incomingMono = incomingTraits.contains(.monoSpace)
        let baseFont = (existingMono || incomingMono)
            ? (existingMono ? existing : incoming)
            : incoming

        // Determine size: non-default size wins (preserves heading sizes)
        let defaultSize = MarkdownTheme.shared.defaultFont.pointSize
        let size: CGFloat
        if existing.pointSize != defaultSize {
            size = existing.pointSize
        } else if incoming.pointSize != defaultSize {
            size = incoming.pointSize
        } else {
            size = incoming.pointSize
        }

        let mergedDescriptor = baseFont.fontDescriptor.withSymbolicTraits(unionTraits)
        if let merged = NSFont(descriptor: mergedDescriptor, size: size),
           merged.fontDescriptor.symbolicTraits.isSuperset(of: unionTraits) {
            return merged
        }

        // baseFont's descriptor couldn't actually resolve every requested
        // trait — most notably, the rounded system design (see
        // MarkdownTheme.roundedFont) has no true italic face and silently
        // drops the trait instead of failing, so nesting bold inside italic
        // (or vice versa) would otherwise lose the italic and render as
        // plain bold. Fall back to the same body-text descriptor
        // MarkdownTheme itself uses for its italic/bold-italic fonts, which
        // does resolve italic correctly.
        let fallbackDescriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
            .withSymbolicTraits(unionTraits)
        return NSFont(descriptor: fallbackDescriptor, size: size) ?? incoming
    }
}
