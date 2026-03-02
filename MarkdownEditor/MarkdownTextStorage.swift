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

        for element in styleMap.elements {
            // Apply content attributes to the full range (including delimiters)
            // so that when delimiters are revealed at cursor, they share the style
            guard element.fullRange.location + element.fullRange.length <= fullRange.length else { continue }
            backingStore.addAttributes(element.attributes, range: element.fullRange)
        }

        // Update delimiter ranges on layout delegates BEFORE glyph generation.
        // This is critical: glyphs are generated lazily and must use current ranges.
        for lm in layoutManagers {
            (lm.delegate as? MarkdownLayoutManagerDelegate)?.updateDelimiters(from: styleMap)
        }

        // Notify that attributes changed
        edited(.editedAttributes, range: fullRange, changeInLength: 0)
    }
}
