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

        for i in 0..<glyphRange.length {
            let charIndex = charIndexes[i]
            if shouldHideCharacter(at: charIndex) {
                modifiedProps[i] = .null
                didModify = true
            } else {
                modifiedProps[i] = props[i]
            }
        }

        if didModify {
            layoutManager.setGlyphs(
                glyphs,
                properties: modifiedProps,
                characterIndexes: charIndexes,
                font: aFont,
                forGlyphRange: glyphRange
            )
            return glyphRange.length
        }

        return 0
    }

    private func shouldHideCharacter(at index: Int) -> Bool {
        // If cursor is in the active span, don't hide its delimiters
        if let active = activeSpanRange, NSLocationInRange(index, active) {
            return false
        }

        return delimiterIndexSet.contains(index)
    }

    func updateDelimiters(from styleMap: MarkdownStyleMap?) {
        guard let ranges = styleMap?.allDelimiterRanges else {
            delimiterIndexSet = IndexSet()
            return
        }
        var indexSet = IndexSet()
        for range in ranges {
            if range.length > 0 {
                indexSet.insert(integersIn: range.location..<(range.location + range.length))
            }
        }
        delimiterIndexSet = indexSet
    }
}
