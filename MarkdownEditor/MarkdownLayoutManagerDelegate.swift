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
            modifiedProps[i] = props[i]
            if shouldHideCharacter(at: charIndexes[i]) {
                modifiedProps[i] = .null
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

    private func shouldHideCharacter(at index: Int) -> Bool {
        // If cursor is in the active span, don't hide its delimiters
        if let active = activeSpanRange, NSLocationInRange(index, active) {
            return false
        }

        return delimiterIndexSet.contains(index)
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
