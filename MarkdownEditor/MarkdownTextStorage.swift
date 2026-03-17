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

    /// Tracks the edited range during processEditing for incremental styling.
    private var pendingEditedRange: NSRange?

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
            }
            return
        }

        // Determine the dirty region: expand editedRange to enclosing paragraph boundaries
        let nsText = text as NSString
        let dirtyRange: NSRange
        if let edited = pendingEditedRange, edited.location != NSNotFound {
            let parStart = nsText.lineRange(for: NSRange(location: edited.location, length: 0)).location
            let editEnd = min(NSMaxRange(edited), nsText.length)
            let parEnd = NSMaxRange(nsText.lineRange(for: NSRange(location: max(0, editEnd > 0 ? editEnd - 1 : 0), length: 0)))
            dirtyRange = NSRange(location: parStart, length: parEnd - parStart)
        } else {
            dirtyRange = fullRange
        }
        let isFullRestyle = NSEqualRanges(dirtyRange, fullRange)

        // Reset attributes only on the dirty region
        backingStore.setAttributes(MarkdownTheme.shared.defaultAttributes, range: dirtyRange)

        // Parse markdown (full AST required — cmark doesn't support incremental)
        let styleMap = MarkdownStyleMap(text: text)
        lastStyleMap = styleMap

        // Apply styles: scope to dirty region for incremental, all for full restyle
        for element in styleMap.elements {
            guard element.fullRange.location + element.fullRange.length <= fullRange.length else { continue }
            if isFullRestyle || NSIntersectionRange(element.fullRange, dirtyRange).length > 0 {
                applyAttributesMergingFontTraits(element.attributes, range: element.fullRange)
            }
        }

        // Style bare URLs and highlights scoped to dirty region
        applyBareURLStyling(text: text, fullRange: dirtyRange)

        let highlightElements = applyHighlightStyling(text: text, fullRange: dirtyRange)
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
    }

    // MARK: - Table overlay text visibility

    /// Makes table text invisible and collapses it to near-zero height,
    /// then adds paragraph spacing on the last line equal to the overlay height
    /// so content below appears right after the overlay.
    func applyTableOverlayAttributes(_ range: NSRange, overlayHeight: CGFloat) {
        let nsText = string as NSString
        guard range.location + range.length <= nsText.length else { return }
        beginEditing()
        // Hide all text in the table range
        backingStore.addAttribute(.foregroundColor, value: NSColor.clear, range: range)

        // Collapse each line to near-zero height using paragraph style
        var lineStart = range.location
        let rangeEnd = NSMaxRange(range)
        while lineStart < rangeEnd {
            let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            let clippedRange = NSIntersectionRange(lineRange, range)
            guard clippedRange.length > 0 else { break }

            let existing = backingStore.attribute(.paragraphStyle, at: clippedRange.location, effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle.default
            let mutable = existing.mutableCopy() as! NSMutableParagraphStyle
            mutable.minimumLineHeight = 0.1
            mutable.maximumLineHeight = 0.1
            mutable.lineSpacing = 0
            mutable.paragraphSpacing = 0
            mutable.paragraphSpacingBefore = 0

            // On the last line, add overlay height + gap as paragraph spacing
            let isLastLine = NSMaxRange(lineRange) >= rangeEnd
            if isLastLine {
                mutable.paragraphSpacing = overlayHeight + 8
            }

            backingStore.addAttribute(.paragraphStyle, value: mutable, range: clippedRange)

            // Also set font to tiny to minimize line fragment height
            backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.1), range: clippedRange)

            lineStart = NSMaxRange(lineRange)
        }

        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Targeted table attribute restore

    /// Restores correct styling on the given ranges without a full AST re-parse.
    /// Uses the cached `lastStyleMap` to re-apply element attributes.
    func restoreTableAttributes(_ ranges: [NSRange]) {
        guard let styleMap = lastStyleMap else {
            // Fallback: full restyle if no cached style map
            applyMarkdownStyling()
            return
        }
        let fullLength = (string as NSString).length
        guard fullLength > 0 else { return }

        beginEditing()
        let theme = MarkdownTheme.shared

        for range in ranges {
            guard range.location + range.length <= fullLength else { continue }

            // 1. Reset to default attributes
            backingStore.setAttributes(theme.defaultAttributes, range: range)

            // 2. Re-apply cached element styles that intersect this range
            for element in styleMap.elements {
                guard element.fullRange.location + element.fullRange.length <= fullLength else { continue }
                let intersection = NSIntersectionRange(element.fullRange, range)
                guard intersection.length > 0 else { continue }
                applyAttributesMergingFontTraits(element.attributes, range: element.fullRange)
            }

            // 3. Re-apply bare URL and highlight styling on this range
            applyBareURLStyling(text: string, fullRange: range)
            let highlightElements = applyHighlightStyling(text: string, fullRange: range)
            if !highlightElements.isEmpty {
                styleMap.appendElements(highlightElements)
            }
        }

        // 4. Update delimiter ranges (unchanged) and notify layout
        for lm in layoutManagers {
            (lm.delegate as? MarkdownLayoutManagerDelegate)?.updateDelimiters(from: styleMap)
            if let container = lm.textContainers.first as? MarkdownTextContainer {
                container.tableLineRanges = styleMap.tableRegions
            }
        }

        edited(.editedAttributes, range: NSRange(location: 0, length: fullLength), changeInLength: 0)
        endEditing()
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

    private func applyHighlightStyling(text: String, fullRange: NSRange) -> [StyledElement] {
        let matches = Self.highlightRegex.matches(in: text, options: [], range: fullRange)
        let highlightAttrs = MarkdownTheme.shared.highlightAttributes
        var elements: [StyledElement] = []

        for match in matches {
            let range = match.range
            guard range.length >= 5 else { continue } // ==x== minimum

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
        return NSFont(descriptor: mergedDescriptor, size: size) ?? incoming
    }
}
