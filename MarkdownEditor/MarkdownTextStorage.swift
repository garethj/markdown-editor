import AppKit

final class MarkdownTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    private(set) var lastStyleMap: MarkdownStyleMap?

    // MARK: - NSTextStorage required overrides

    override var string: String {
        backingStore.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Styling

    override func processEditing() {
        if editedMask.contains(.editedCharacters) {
            applyMarkdownStyling()
        }
        super.processEditing()
    }

    func applyMarkdownStyling() {
        let text = string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else {
            lastStyleMap = nil
            // Clear delimiter ranges on all layout delegates
            for lm in layoutManagers {
                (lm.delegate as? MarkdownLayoutManagerDelegate)?.updateDelimiters(from: nil)
            }
            return
        }

        // Reset to default attributes (directly on backing store to avoid recursion)
        backingStore.setAttributes(MarkdownTheme.shared.defaultAttributes, range: fullRange)

        // Parse markdown and apply styles
        let styleMap = MarkdownStyleMap(text: text)
        lastStyleMap = styleMap

        // Elements are ordered parent-before-child (walker appends then calls descendInto).
        // This ordering is critical: when a child range overlaps a parent, the merge
        // below unions font traits so nested formatting (e.g. bold inside italic) works.
        for element in styleMap.elements {
            // Apply content attributes to the full range (including delimiters)
            // so that when delimiters are revealed at cursor, they share the style
            guard element.fullRange.location + element.fullRange.length <= fullRange.length else { continue }
            applyAttributesMergingFontTraits(element.attributes, range: element.fullRange)
        }

        // Update delimiter ranges on layout delegates BEFORE glyph generation.
        // This is critical: glyphs are generated lazily and must use current ranges.
        for lm in layoutManagers {
            (lm.delegate as? MarkdownLayoutManagerDelegate)?.updateDelimiters(from: styleMap)
        }

        // Notify that attributes changed
        edited(.editedAttributes, range: fullRange, changeInLength: 0)
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
        return NSFont(descriptor: mergedDescriptor, size: size) ?? incoming
    }
}
