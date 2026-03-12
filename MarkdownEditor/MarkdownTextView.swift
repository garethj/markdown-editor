import AppKit
import SwiftUI

// MARK: - Editor view (SwiftUI wrapper)

struct EditorView: View {
    @ObservedObject var document: MarkdownDocument
    @Environment(\.undoManager) var undoManager

    var body: some View {
        VStack(spacing: 0) {
            MarkdownTextView(document: document, undoManager: undoManager)
            StatusBarView(text: document.text)
        }
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    let text: String

    private var wordCount: Int {
        guard !text.isEmpty else { return 0 }
        return text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var characterCount: Int {
        text.count
    }

    var body: some View {
        HStack {
            Spacer()
            Text("\(wordCount) words  \(characterCount) characters")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - NSTextView subclass with keyboard shortcuts

final class EditorTextView: NSTextView {
    var formatHandler: ((FormatAction) -> Void)?
    var findHandler: ((FindAction) -> Void)?

    enum FormatAction {
        case bold, italic, link, codeBlock, heading(Int), highlight
    }

    enum FindAction {
        case show, nextMatch, previousMatch, dismiss
    }

    // MARK: - Cmd+click to open links

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let url = linkURL(at: event) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    // Show pointing hand cursor when Cmd is held over a link
    override func mouseMoved(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           linkURL(at: event) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        updateLinkCursor(with: event)
        super.flagsChanged(with: event)
    }

    private func updateLinkCursor(with event: NSEvent) {
        guard let window else { return }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else { return }

        if event.modifierFlags.contains(.command) {
            let charIndex = characterIndex(at: localPoint)
            if charIndex < (string as NSString).length,
               let urlString = textStorage?.attribute(.markdownLinkURL, at: charIndex, effectiveRange: nil) as? String,
               URL(string: urlString) != nil {
                NSCursor.pointingHand.set()
                return
            }
        }
        NSCursor.iBeam.set()
    }

    private func linkURL(at event: NSEvent) -> URL? {
        let localPoint = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndex(at: localPoint)
        guard charIndex < (string as NSString).length else { return nil }
        guard let urlString = textStorage?.attribute(.markdownLinkURL, at: charIndex, effectiveRange: nil) as? String,
              let url = URL(string: urlString) else { return nil }
        return url
    }

    private func characterIndex(at point: NSPoint) -> Int {
        guard let textContainer, let layoutManager else { return NSNotFound }
        let textPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        return layoutManager.characterIndex(
            for: textPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        let chars = event.charactersIgnoringModifiers ?? ""

        switch chars {
        case "b":
            formatHandler?(.bold)
            return true
        case "i":
            formatHandler?(.italic)
            return true
        case "f":
            findHandler?(.show)
            return true
        case "g":
            if event.modifierFlags.contains(.shift) {
                findHandler?(.previousMatch)
            } else {
                findHandler?(.nextMatch)
            }
            return true
        case "m", "M" where event.modifierFlags.contains(.shift):
            formatHandler?(.highlight)
            return true
        case "k":
            if event.modifierFlags.contains(.shift) {
                formatHandler?(.codeBlock)
            } else {
                formatHandler?(.link)
            }
            return true
        case "1" where event.modifierFlags.contains(.command):
            formatHandler?(.heading(1))
            return true
        case "2" where event.modifierFlags.contains(.command):
            formatHandler?(.heading(2))
            return true
        case "3" where event.modifierFlags.contains(.command):
            formatHandler?(.heading(3))
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

// MARK: - NSViewRepresentable bridge

struct MarkdownTextView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var undoManager: UndoManager?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // Build TextKit 1 stack
        let textStorage = MarkdownTextStorage()
        let layoutManager = NSLayoutManager()
        let containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = MarkdownTextContainer(containerSize: containerSize)

        // We manage container width manually to allow table lines to exceed view width
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        // Layout manager delegate for glyph hiding
        let layoutDelegate = MarkdownLayoutManagerDelegate()
        layoutManager.delegate = layoutDelegate
        context.coordinator.layoutDelegate = layoutDelegate
        context.coordinator.markdownTextStorage = textStorage

        // Create text view
        let textView = EditorTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.font = MarkdownTheme.shared.defaultFont
        textView.textColor = MarkdownTheme.shared.defaultColor
        textView.backgroundColor = MarkdownTheme.shared.backgroundColor
        textView.insertionPointColor = MarkdownTheme.shared.cursorColor
        textView.textContainerInset = NSSize(width: 40, height: 20)
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Format action handler
        textView.formatHandler = { [weak coordinator = context.coordinator] action in
            coordinator?.handleFormatAction(action)
        }

        scrollView.documentView = textView

        // Set initial prose width before loading content so layout uses correct width.
        // Use a reasonable default; refined with actual clip view width below.
        textContainer.proseWidth = 600

        // Observe clip view bounds changes to keep container width in sync
        context.coordinator.observeClipViewBounds(scrollView: scrollView)

        // Find action handler
        textView.findHandler = { [weak coordinator = context.coordinator] action in
            coordinator?.handleFindAction(action)
        }

        // Set up find bar
        context.coordinator.setupFindBar()

        // Set initial content
        if !document.text.isEmpty {
            textStorage.replaceCharacters(
                in: NSRange(location: 0, length: 0),
                with: document.text
            )
        }

        // Refine prose width once clip view is sized
        DispatchQueue.main.async {
            let clipWidth = scrollView.contentView.bounds.width
            if clipWidth > 0 {
                let pw = clipWidth - textView.textContainerInset.width * 2
                textContainer.proseWidth = pw
                // Force re-layout with correct width
                if let lm = textView.layoutManager {
                    let len = (textView.string as NSString).length
                    if len > 0 {
                        lm.invalidateLayout(
                            forCharacterRange: NSRange(location: 0, length: len),
                            actualCharacterRange: nil)
                    }
                }
            }
        }

        // applyMarkdownStyling is already called inside replaceCharacters→processEditing,
        // and it updates the layout delegate's delimiter ranges internally.
        // No additional calls needed here.

        // Observe appearance changes for dark mode
        context.coordinator.observeAppearance()

        // Set window frame autosave so macOS remembers size/position across launches
        DispatchQueue.main.async {
            scrollView.window?.setFrameAutosaveName("MarkdownEditorDocument")
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        guard !context.coordinator.isUpdatingDocument else { return }

        let current = textView.string
        if current != document.text {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selection = textView.selectedRanges
            textView.textStorage?.replaceCharacters(
                in: NSRange(location: 0, length: (current as NSString).length),
                with: document.text
            )
            // applyMarkdownStyling + delimiter update handled inside processEditing
            // Restore selection safely
            let maxLen = (textView.string as NSString).length
            let safeRanges = selection.map { val -> NSValue in
                let r = val.rangeValue
                let loc = min(r.location, maxLen)
                let len = min(r.length, maxLen - loc)
                return NSValue(range: NSRange(location: loc, length: len))
            }
            textView.selectedRanges = safeRanges
            context.coordinator.isUpdatingFromSwiftUI = false
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: EditorTextView?
        var markdownTextStorage: MarkdownTextStorage?
        var layoutDelegate: MarkdownLayoutManagerDelegate?
        var isUpdatingDocument = false
        var isUpdatingFromSwiftUI = false
        private var fileWatcher: FileWatcher?
        private var appearanceObserver: NSObjectProtocol?
        private var clipViewBoundsObserver: NSObjectProtocol?

        // Find bar
        let findState = FindState()
        var findBarView: FindBarView?
        var findBarAccessory: NSTitlebarAccessoryViewController?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        deinit {
            if let obs = appearanceObserver {
                DistributedNotificationCenter.default().removeObserver(obs)
            }
            if let obs = clipViewBoundsObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            fileWatcher?.stop()
        }

        // MARK: - Clip view bounds tracking

        func observeClipViewBounds(scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            clipViewBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] notification in
                guard let clipView = notification.object as? NSClipView,
                      let textView = self?.textView,
                      let container = textView.textContainer as? MarkdownTextContainer
                else { return }
                let newWidth = clipView.bounds.width - textView.textContainerInset.width * 2
                if newWidth > 0, abs(container.proseWidth - newWidth) > 1 {
                    container.proseWidth = newWidth
                    textView.needsLayout = true
                    textView.needsDisplay = true
                }
            }
        }

        // MARK: - Appearance

        func observeAppearance() {
            appearanceObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshTheme()
            }
        }

        private func refreshTheme() {
            guard let textView else { return }
            MarkdownTheme.shared.updateForCurrentAppearance()
            textView.backgroundColor = MarkdownTheme.shared.backgroundColor
            textView.insertionPointColor = MarkdownTheme.shared.cursorColor
            markdownTextStorage?.applyMarkdownStyling()
            // Delimiter ranges updated inside applyMarkdownStyling
            if let lm = textView.layoutManager {
                let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
                if fullRange.length > 0 {
                    lm.invalidateGlyphs(forCharacterRange: fullRange, changeInLength: 0, actualCharacterRange: nil)
                    lm.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
                }
            }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI else { return }
            guard let textView = notification.object as? NSTextView else { return }

            isUpdatingDocument = true
            parent.document.text = textView.string

            // Register undo for dirty tracking
            if let undoMgr = parent.undoManager {
                undoMgr.registerUndo(withTarget: parent.document) { doc in
                    // The undo manager just needs a registered action for dirty tracking
                    _ = doc.text
                }
            }
            isUpdatingDocument = false

            // Delimiter ranges and glyph invalidation are already handled inside
            // processEditing → applyMarkdownStyling → edited(.editedAttributes).
            // No full-document invalidation needed here — it's expensive (O(n) per
            // keystroke) and causes the scroll view to jump to the bottom.
            updateCursorReveal()

            // Re-run find if the find bar is visible
            if isFindBarVisible {
                performSearch(query: findState.searchText)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateCursorReveal()
        }

        // MARK: - Cursor-aware reveal

        private func updateCursorReveal() {
            guard let textView,
                  let layoutDelegate,
                  let styleMap = markdownTextStorage?.lastStyleMap
            else { return }

            let cursorPos = textView.selectedRange().location
            let oldActive = layoutDelegate.activeSpanRange

            // Find the element the cursor is in
            var newActive: NSRange?
            for element in styleMap.elements where !element.delimiterRanges.isEmpty {
                if NSLocationInRange(cursorPos, element.fullRange)
                    || cursorPos == NSMaxRange(element.fullRange) {
                    newActive = element.fullRange
                    break
                }
            }

            guard oldActive != newActive else { return }
            layoutDelegate.activeSpanRange = newActive

            // Invalidate glyph layout for old and new ranges
            if let lm = textView.layoutManager {
                let textLen = (textView.string as NSString).length
                if let old = oldActive, old.location + old.length <= textLen {
                    lm.invalidateGlyphs(forCharacterRange: old, changeInLength: 0, actualCharacterRange: nil)
                    lm.invalidateLayout(forCharacterRange: old, actualCharacterRange: nil)
                }
                if let new = newActive, new.location + new.length <= textLen {
                    lm.invalidateGlyphs(forCharacterRange: new, changeInLength: 0, actualCharacterRange: nil)
                    lm.invalidateLayout(forCharacterRange: new, actualCharacterRange: nil)
                }
                textView.needsDisplay = true
            }
        }

        // MARK: - Format actions

        func handleFormatAction(_ action: EditorTextView.FormatAction) {
            switch action {
            case .bold: toggleWrap(prefix: "**", suffix: "**")
            case .italic: toggleWrap(prefix: "_", suffix: "_")
            case .link: insertLink()
            case .codeBlock: insertCodeBlock()
            case .highlight: toggleWrap(prefix: "==", suffix: "==")
            case .heading(let level): setHeading(level: level)
            }
        }

        private func toggleWrap(prefix: String, suffix: String) {
            guard let textView else { return }
            let range = textView.selectedRange()
            let text = textView.string as NSString
            let pLen = prefix.count
            let sLen = suffix.count

            // Check if delimiters are outside the selection
            if range.location >= pLen,
               NSMaxRange(range) + sLen <= text.length {
                let before = text.substring(with: NSRange(location: range.location - pLen, length: pLen))
                let after = text.substring(with: NSRange(location: NSMaxRange(range), length: sLen))
                if before == prefix, after == suffix {
                    let fullRange = NSRange(location: range.location - pLen,
                                            length: range.length + pLen + sLen)
                    let inner = text.substring(with: range)
                    textView.insertText(inner, replacementRange: fullRange)
                    textView.setSelectedRange(NSRange(location: range.location - pLen, length: range.length))
                    return
                }
            }

            // Check if delimiters are inside the selection
            if range.length >= pLen + sLen {
                let selected = text.substring(with: range)
                if selected.hasPrefix(prefix), selected.hasSuffix(suffix) {
                    let inner = (selected as NSString).substring(with: NSRange(location: pLen, length: range.length - pLen - sLen))
                    textView.insertText(inner, replacementRange: range)
                    textView.setSelectedRange(NSRange(location: range.location, length: inner.count))
                    return
                }
            }

            let selected = text.substring(with: range)
            let wrapped = "\(prefix)\(selected)\(suffix)"
            textView.insertText(wrapped, replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + pLen, length: range.length))
        }

        private func insertLink() {
            guard let textView else { return }
            let range = textView.selectedRange()
            let selected = (textView.string as NSString).substring(with: range)
            let linkText = "[\(selected)](url)"
            textView.insertText(linkText, replacementRange: range)
            // Select "url" for easy replacement
            let urlStart = range.location + selected.count + 3
            textView.setSelectedRange(NSRange(location: urlStart, length: 3))
        }

        private func insertCodeBlock() {
            guard let textView else { return }
            let range = textView.selectedRange()
            let selected = (textView.string as NSString).substring(with: range)
            let code = "```\n\(selected)\n```"
            textView.insertText(code, replacementRange: range)
        }

        private func setHeading(level: Int) {
            guard let textView else { return }
            let text = textView.string as NSString
            let range = textView.selectedRange()
            let lineRange = text.lineRange(for: range)
            var line = text.substring(with: lineRange)

            // Remove existing heading prefix
            while line.hasPrefix("#") {
                line = String(line.dropFirst())
            }
            if line.hasPrefix(" ") {
                line = String(line.dropFirst())
            }

            let prefix = String(repeating: "#", count: level) + " "
            let newLine = prefix + line
            textView.insertText(newLine, replacementRange: lineRange)
        }

        // MARK: - Find bar

        func setupFindBar() {
            let bar = FindBarView()
            findBarView = bar

            bar.onSearchTextChanged = { [weak self] query in
                self?.performSearch(query: query)
            }
            bar.onNext = { [weak self] in
                self?.goToNextMatch()
            }
            bar.onPrevious = { [weak self] in
                self?.goToPreviousMatch()
            }
            bar.onClose = { [weak self] in
                self?.dismissFindBar()
            }

            let accessory = NSTitlebarAccessoryViewController()
            bar.frame = NSRect(x: 0, y: 0, width: 400, height: 33)
            accessory.view = bar
            accessory.layoutAttribute = .bottom
            findBarAccessory = accessory
        }

        func handleFindAction(_ action: EditorTextView.FindAction) {
            switch action {
            case .show:
                showFindBar()
            case .nextMatch:
                goToNextMatch()
            case .previousMatch:
                goToPreviousMatch()
            case .dismiss:
                dismissFindBar()
            }
        }

        private var isFindBarVisible: Bool {
            findBarAccessory?.parent != nil
        }

        func showFindBar() {
            guard let bar = findBarView, let textView,
                  let window = textView.window,
                  let accessory = findBarAccessory else { return }

            // Add accessory to window if not already present
            if accessory.parent == nil {
                window.addTitlebarAccessoryViewController(accessory)
            }

            // Pre-fill with selection
            let sel = textView.selectedRange()
            if sel.length > 0, sel.length < 200 {
                let selected = (textView.string as NSString).substring(with: sel)
                bar.searchText = selected
            }

            bar.focusSearchField()
            performSearch(query: bar.searchText)
        }

        func dismissFindBar() {
            guard let bar = findBarView, let textView,
                  let accessory = findBarAccessory else { return }

            clearHighlights()
            findState.searchText = ""
            findState.matches.removeAll()
            bar.updateMatchLabel(current: 0, total: 0)

            // Remove accessory from window
            if let window = textView.window,
               let idx = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
                window.removeTitlebarAccessoryViewController(at: idx)
            }

            textView.window?.makeFirstResponder(textView)
        }

        func performSearch(query: String) {
            guard let textView, let lm = textView.layoutManager else { return }
            findState.searchText = query
            clearHighlights()

            let text = textView.string as NSString
            findState.search(in: text, for: query)

            // Highlight all matches
            let theme = MarkdownTheme.shared
            for range in findState.matches {
                lm.addTemporaryAttribute(
                    .backgroundColor,
                    value: theme.findMatchColor,
                    forCharacterRange: range
                )
            }

            // Highlight current match
            if !findState.matches.isEmpty {
                // Find nearest match to cursor
                let cursorPos = textView.selectedRange().location
                var bestIdx = 0
                var bestDist = Int.max
                for (i, r) in findState.matches.enumerated() {
                    let dist = abs(r.location - cursorPos)
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }
                findState.currentMatchIndex = bestIdx
                highlightCurrentMatch()
                scrollToCurrentMatch()
            }

            findBarView?.updateMatchLabel(
                current: findState.currentMatchIndex,
                total: findState.matches.count
            )
        }

        func goToNextMatch() {
            guard !findState.matches.isEmpty else { return }
            unhighlightCurrentMatch()
            findState.nextMatch()
            highlightCurrentMatch()
            scrollToCurrentMatch()
            findBarView?.updateMatchLabel(
                current: findState.currentMatchIndex,
                total: findState.matches.count
            )
        }

        func goToPreviousMatch() {
            guard !findState.matches.isEmpty else { return }
            unhighlightCurrentMatch()
            findState.previousMatch()
            highlightCurrentMatch()
            scrollToCurrentMatch()
            findBarView?.updateMatchLabel(
                current: findState.currentMatchIndex,
                total: findState.matches.count
            )
        }

        private func clearHighlights() {
            guard let textView, let lm = textView.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard fullRange.length > 0 else { return }
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        }

        private func highlightCurrentMatch() {
            guard let textView, let lm = textView.layoutManager,
                  !findState.matches.isEmpty else { return }
            let range = findState.matches[findState.currentMatchIndex]
            lm.addTemporaryAttribute(
                .backgroundColor,
                value: MarkdownTheme.shared.findCurrentMatchColor,
                forCharacterRange: range
            )
        }

        private func unhighlightCurrentMatch() {
            guard let textView, let lm = textView.layoutManager,
                  !findState.matches.isEmpty else { return }
            let range = findState.matches[findState.currentMatchIndex]
            lm.addTemporaryAttribute(
                .backgroundColor,
                value: MarkdownTheme.shared.findMatchColor,
                forCharacterRange: range
            )
        }

        private func scrollToCurrentMatch() {
            guard let textView, !findState.matches.isEmpty else { return }
            let range = findState.matches[findState.currentMatchIndex]
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }

        // MARK: - File watching

        func startWatching(url: URL) {
            fileWatcher?.stop()
            fileWatcher = FileWatcher()
            fileWatcher?.onChange = { [weak self] event in
                self?.handleFileEvent(event, url: url)
            }
            fileWatcher?.start(url: url)
        }

        private func handleFileEvent(_ event: FileWatcher.Event, url: URL) {
            switch event {
            case .modified:
                handleExternalModification(url: url)
            case .deleted, .renamed:
                // File gone — stop watching, keep current content
                fileWatcher?.stop()
            }
        }

        private func handleExternalModification(url: URL) {
            guard let newData = try? Data(contentsOf: url),
                  let newText = String(data: newData, encoding: .utf8)
            else { return }

            let doc = parent.document
            let hasLocalChanges = (parent.undoManager?.canUndo ?? false)

            if hasLocalChanges {
                // Show conflict alert
                let alert = NSAlert()
                alert.messageText = "File Changed"
                alert.informativeText = "This file was modified externally. What would you like to do?"
                alert.addButton(withTitle: "Reload")
                alert.addButton(withTitle: "Keep Mine")
                alert.alertStyle = .warning

                if let window = textView?.window {
                    alert.beginSheetModal(for: window) { response in
                        if response == .alertFirstButtonReturn {
                            doc.text = newText
                        }
                    }
                }
            } else {
                doc.text = newText
            }
        }
    }
}

// MARK: - NSRange equality helper

private func == (lhs: NSRange?, rhs: NSRange?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case let (.some(l), .some(r)): return NSEqualRanges(l, r)
    default: return false
    }
}

private func != (lhs: NSRange?, rhs: NSRange?) -> Bool {
    !(lhs == rhs)
}
