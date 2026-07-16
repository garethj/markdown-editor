import AppKit
import CoreText

final class MarkdownLayoutManagerDelegate: NSObject, NSLayoutManagerDelegate {
    var delimiterIndexSet = IndexSet()
    var activeSpanRange: NSRange?
    /// Character index → replacement character whose glyph (in the same font)
    /// should be drawn instead — used to reshape list bullets into circles/
    /// diamonds without altering the saved markdown source.
    var glyphSubstitutions: [Int: Character] = [:]

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !delimiterIndexSet.isEmpty || !glyphSubstitutions.isEmpty else { return 0 }

        let modifiedProps = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(
            capacity: glyphRange.length
        )
        let modifiedGlyphs = UnsafeMutablePointer<CGGlyph>.allocate(capacity: glyphRange.length)
        defer {
            modifiedProps.deallocate()
            modifiedGlyphs.deallocate()
        }

        var didModify = false

        for i in 0..<glyphRange.length {
            let charIndex = charIndexes[i]
            modifiedGlyphs[i] = glyphs[i]
            modifiedProps[i] = props[i]

            if shouldHideCharacter(at: charIndex) {
                modifiedProps[i] = .null
                didModify = true
            } else if let replacement = glyphSubstitutions[charIndex],
                      let substituteGlyph = Self.glyphID(for: replacement, in: aFont) {
                modifiedGlyphs[i] = substituteGlyph
                didModify = true
            }
        }

        if didModify {
            layoutManager.setGlyphs(
                modifiedGlyphs,
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

    /// Looks up the glyph ID for a character within a specific font, caching
    /// the result — this runs per on-screen glyph, same cost profile as the
    /// existing delimiter-hiding path. Returns nil (leaving the original
    /// glyph in place) if the font has no glyph for that character.
    private static var glyphCache: [String: CGGlyph] = [:]

    private static func glyphID(for character: Character, in font: NSFont) -> CGGlyph? {
        let cacheKey = "\(font.fontName)|\(character)"
        if let cached = glyphCache[cacheKey] {
            return cached
        }
        let utf16 = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(font as CTFont, utf16, &glyphs, utf16.count),
              let glyph = glyphs.first, glyph != 0
        else { return nil }
        glyphCache[cacheKey] = glyph
        return glyph
    }

    func updateDelimiters(from styleMap: MarkdownStyleMap?) {
        guard let styleMap else {
            delimiterIndexSet = IndexSet()
            glyphSubstitutions = [:]
            return
        }
        var indexSet = IndexSet()
        for range in styleMap.allDelimiterRanges {
            if range.length > 0 {
                indexSet.insert(integersIn: range.location..<(range.location + range.length))
            }
        }
        delimiterIndexSet = indexSet
        glyphSubstitutions = Dictionary(
            uniqueKeysWithValues: styleMap.listMarkerGlyphOverrides.map { ($0.location, $0.character) }
        )
    }
}
