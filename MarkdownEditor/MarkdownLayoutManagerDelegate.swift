import AppKit

final class MarkdownLayoutManagerDelegate: NSObject, NSLayoutManagerDelegate {
    var delimiterRanges: [NSRange] = []
    var activeSpanRange: NSRange?

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !delimiterRanges.isEmpty else { return 0 }

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

        for range in delimiterRanges {
            if NSLocationInRange(index, range) {
                return true
            }
        }
        return false
    }

    func updateDelimiters(from styleMap: MarkdownStyleMap?) {
        delimiterRanges = styleMap?.allDelimiterRanges ?? []
    }
}
