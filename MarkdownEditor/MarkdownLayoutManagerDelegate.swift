import AppKit

final class MarkdownLayoutManagerDelegate: NSObject, NSLayoutManagerDelegate {
    var delimiterIndexSet = IndexSet()
    var activeSpanRange: NSRange?

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !delimiterIndexSet.isEmpty else { return 0 }

        let modifiedProps = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(
            capacity: glyphRange.length
        )
        defer { modifiedProps.deallocate() }

        var didModify = false

        // Hidden characters are marked .controlCharacter and given zero
        // advancement (below), not .null. A .null glyph at the very start of
        // a paragraph — a task item's hidden "-", a heading's "#" — gets
        // swept into the *previous* paragraph's last line fragment, so this
        // paragraph's first fragment starts one character in and the
        // typesetter treats it as a continuation line, indenting it by the
        // paragraph style's headIndent. The very first paragraph in a
        // document has no previous fragment to absorb it, which is why only
        // later ones shifted.
        for i in 0..<glyphRange.length {
            modifiedProps[i] = props[i]
            if shouldHideCharacter(at: charIndexes[i]) {
                modifiedProps[i] = .controlCharacter
                didModify = true
            }
        }

        guard didModify else { return 0 }

        layoutManager.setGlyphs(
            glyphs,
            properties: modifiedProps,
            characterIndexes: charIndexes,
            font: aFont,
            forGlyphRange: glyphRange
        )
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        shouldHideCharacter(at: charIndex) ? .zeroAdvancement : action
    }

    private func shouldHideCharacter(at index: Int) -> Bool {
        // If cursor is in the active span, don't hide its delimiters
        if let active = activeSpanRange, NSLocationInRange(index, active) {
            return false
        }

        return delimiterIndexSet.contains(index)
    }

    /// Keeps the hidden-character set aligned with the text after an edit
    /// whose restyle has been deferred (see `MarkdownTextStorage.processEditing`).
    /// Every index after the edit moved by `delta`, and the characters just
    /// typed aren't delimiters until the next parse says otherwise — without
    /// this, glyph hiding would blank out the wrong characters for as long as
    /// the restyle stayed pending.
    func adjustForEdit(at location: Int, delta: Int, editedRange: NSRange) {
        if delta != 0 {
            delimiterIndexSet.shift(startingAt: location, by: delta)
            if var active = activeSpanRange {
                if active.location >= location {
                    active.location = max(0, active.location + delta)
                } else if location < NSMaxRange(active) {
                    active.length = max(0, active.length + delta)
                }
                activeSpanRange = active
            }
        }
        if editedRange.length > 0 {
            delimiterIndexSet.remove(integersIn: editedRange.location..<NSMaxRange(editedRange))
        }
    }

    func updateDelimiters(from styleMap: MarkdownStyleMap?) {
        guard let styleMap else {
            delimiterIndexSet = IndexSet()
            return
        }
        var indexSet = IndexSet()
        for range in styleMap.allDelimiterRanges {
            if range.length > 0 {
                indexSet.insert(integersIn: range.location..<(range.location + range.length))
            }
        }
        delimiterIndexSet = indexSet
    }
}
