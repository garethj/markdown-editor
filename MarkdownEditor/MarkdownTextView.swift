import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editor view (SwiftUI wrapper)

struct EditorView: View {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    @Environment(\.undoManager) var undoManager
    @StateObject private var tocModel = TableOfContentsModel()
    @State private var showTOC: Bool

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _showTOC = State(initialValue: Self.headingCount(in: document.text) > 1)
    }

    var body: some View {
        if document.didConfirmLargeFileLoad {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    MarkdownTextView(document: document, fileURL: fileURL, undoManager: undoManager, tocModel: tocModel)
                    if showTOC {
                        Divider()
                        TableOfContentsView(model: tocModel)
                            .frame(width: 220)
                    }
                }
                StatusBarView(text: document.text, hasUnsavedChanges: document.text != document.lastConfirmedSavedText)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        showTOC.toggle()
                    } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .help(showTOC ? "Hide Table of Contents" : "Show Table of Contents")
                }
            }
        } else {
            LargeFileWarningView(
                fileSizeBytes: document.fileSizeBytes,
                onOpenAnyway: { document.didConfirmLargeFileLoad = true },
                onCancel: { NSApp.keyWindow?.performClose(nil) }
            )
        }
    }

    /// Crude but cheap heading count for the initial sidebar-visibility default,
    /// computed once from the raw text before any AST parse has happened.
    private static func headingCount(in text: String) -> Int {
        var count = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#") else { continue }
            var hashes = 0
            for ch in line {
                if ch == "#" { hashes += 1 } else { break }
            }
            guard hashes >= 1 && hashes <= 6 else { continue }
            let rest = line.dropFirst(hashes)
            if rest.isEmpty || rest.first == " " {
                count += 1
            }
        }
        return count
    }
}

// MARK: - Large file warning

struct LargeFileWarningView: View {
    let fileSizeBytes: Int
    let onOpenAnyway: () -> Void
    let onCancel: () -> Void

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSizeBytes), countStyle: .file)
    }

    private var formattedThreshold: String {
        ByteCountFormatter.string(fromByteCount: Int64(MarkdownDocument.largeFileThresholdBytes), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Large File")
                .font(.title2)
                .bold()
            Text("This file is \(formattedSize), larger than the recommended \(formattedThreshold) limit. Editing large files can be slow — every keystroke re-parses the whole document.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Open Anyway", action: onOpenAnyway)
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    let text: String
    let hasUnsavedChanges: Bool
    @StateObject private var counter = DebouncedWordCounter()

    var body: some View {
        HStack {
            if hasUnsavedChanges {
                Text("Unsaved Changes")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
            Spacer()
            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        .padding(.leading, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: text) { _, newText in
            counter.schedule(newText)
        }
        .onAppear {
            counter.computeNow(text)
        }
    }

    private var statusText: String {
        var text = "\(counter.wordCount.formatted()) words / \(counter.characterCount.formatted()) characters"
        if counter.readingTimeMinutes > 0 {
            text += " (\(counter.readingTimeMinutes) min read)"
        }
        return text
    }
}

private final class DebouncedWordCounter: ObservableObject {
    @Published var wordCount: Int = 0
    @Published var characterCount: Int = 0
    @Published var readingTimeMinutes: Int = 0
    private static let averageWordsPerMinute = 200.0
    private var debounceItem: DispatchWorkItem?

    func schedule(_ text: String) {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.computeNow(text)
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func computeNow(_ text: String) {
        characterCount = text.count
        if text.isEmpty {
            wordCount = 0
            readingTimeMinutes = 0
        } else {
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            wordCount = words
            readingTimeMinutes = max(1, Int(ceil(Double(words) / Self.averageWordsPerMinute)))
        }
    }
}

// MARK: - NSTextView subclass with keyboard shortcuts

final class EditorTextView: NSTextView {
    var formatHandler: ((FormatAction) -> Void)?
    var findHandler: ((FindAction) -> Void)?
    var checkboxClickHandler: ((Int) -> Bool)?

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
        if event.clickCount == 1 {
            let localPoint = convert(event.locationInWindow, from: nil)
            let charIndex = characterIndex(at: localPoint)
            if charIndex < (string as NSString).length,
               checkboxClickHandler?(charIndex) == true {
                return
            }
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

// MARK: - Scroll view with window-frame restore

/// Restores the window's saved frame the moment this view attaches to a window,
/// racing SwiftUI's own `.defaultSize` application for that scene. Doing this
/// synchronously in `viewDidMoveToWindow` (rather than via `DispatchQueue.main.async`,
/// which cedes a full run-loop turn) wins that race in the common case; the two
/// follow-up rechecks catch the rarer case where SwiftUI's own sizing pass is
/// itself deferred and still clobbers the restored frame after we've set it.
final class MarkdownScrollView: NSScrollView {
    private static let frameAutosaveName = "MarkdownEditorDocument"
    private var didRestoreFrame = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !didRestoreFrame else { return }
        didRestoreFrame = true

        window.setFrameAutosaveName(Self.frameAutosaveName)
        let restoredFrame = window.frame

        func reassertIfClobbered() {
            if window.frame != restoredFrame {
                window.setFrame(restoredFrame, display: true)
            }
        }
        DispatchQueue.main.async { reassertIfClobbered() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reassertIfClobbered() }
    }
}

// MARK: - NSViewRepresentable bridge

struct MarkdownTextView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    var undoManager: UndoManager?
    var tocModel: TableOfContentsModel?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MarkdownScrollView()
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

        // Checkbox click handler (task-list toggle)
        textView.checkboxClickHandler = { [weak coordinator = context.coordinator] charIndex in
            coordinator?.handleCheckboxClick(at: charIndex) ?? false
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
        context.coordinator.updateTOC()

        // Refine prose width once clip view is sized
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            let clipWidth = scrollView.contentView.bounds.width
            if clipWidth > 0 {
                let pw = clipWidth - textView.textContainerInset.width * 2
                textContainer.proseWidth = pw
                textView.minSize = NSSize(width: clipWidth, height: 0)
                textView.frame.size.width = max(clipWidth, textContainer.size.width)
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

        // Observe PDF export notification
        context.coordinator.observeExportToPDF()

        // Start file watching if we have a URL
        if let url = fileURL {
            context.coordinator.startWatching(url: url)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        guard !context.coordinator.isUpdatingDocument else { return }

        // Update file watching if URL changed (e.g. Save As)
        if let url = fileURL {
            context.coordinator.startWatching(url: url)
        }

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
            context.coordinator.updateTOC()
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
        private var watchedURL: URL?
        private var appearanceObserver: NSObjectProtocol?
        private var clipViewBoundsObserver: NSObjectProtocol?
        private var clipViewFrameObserver: NSObjectProtocol?
        private var exportObserver: NSObjectProtocol?
        private var pdfExporter: MarkdownPDFExporter?

        // Find bar
        let findState = FindState()
        var findBarView: FindBarView?
        var findBarAccessory: NSTitlebarAccessoryViewController?
        private var pendingFindWorkItem: DispatchWorkItem?

        // Save verification (confirms writes actually reached disk).
        // A set, not a single slot: overlapping saves (e.g. autosave firing,
        // then a manual Cmd+S before the autosave's own disk-echo has round-tripped
        // back through the file watcher) must each be independently confirmable —
        // a single shared slot would let a newer save's expected text clobber an
        // older save's, so the older save's echo would match neither
        // `lastConfirmedSavedText` nor the (now-overwritten) expectation and get
        // mistaken for a real external conflict.
        private var pendingSaveTexts: Set<String> = []

        init(_ parent: MarkdownTextView) {
            self.parent = parent
            super.init()
            parent.document.onWillSave = { [weak self] savedText in
                self?.scheduleSaveVerification(expecting: savedText)
            }
            parent.tocModel?.onSelect = { [weak self] range in
                self?.scrollToHeading(range)
            }
        }

        deinit {
            if let obs = appearanceObserver {
                DistributedNotificationCenter.default().removeObserver(obs)
            }
            if let obs = clipViewBoundsObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = clipViewFrameObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = exportObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            fileWatcher?.stop()
        }

        // MARK: - Clip view bounds tracking

        /// Coalesce flag to prevent duplicate handling when both bounds and frame fire together
        private var clipViewUpdateScheduled = false

        /// The clip view origin as of the end of the last `handleClipViewChange` call.
        /// Notifications are coalesced (see below), so by the time this method runs the
        /// clip view's *current* bounds may already reflect a spurious mid-transition
        /// drift — this tracks the last known-good origin instead, so we can tell "was
        /// genuinely at the top/left before this resize" from "the resize itself moved
        /// us away from the top/left."
        private var lastStableClipOrigin: NSPoint = .zero

        func observeClipViewBounds(scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true

            let handler: (Notification) -> Void = { [weak self] _ in
                guard let self, !self.clipViewUpdateScheduled else { return }
                self.clipViewUpdateScheduled = true
                DispatchQueue.main.async {
                    self.clipViewUpdateScheduled = false
                    self.handleClipViewChange(clipView)
                }
            }

            clipViewBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main,
                using: handler
            )
            clipViewFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clipView,
                queue: .main,
                using: handler
            )
        }

        private func handleClipViewChange(_ clipView: NSClipView) {
            guard let textView,
                  let container = textView.textContainer as? MarkdownTextContainer
            else { return }

            // A width-driven reflow (see below) changes the document's total height,
            // and NSClipView's own point-based scroll preservation across that kind
            // of resize can leave a small spurious residual offset — concretely
            // measured as ~10pt of vertical drift when entering full screen while
            // already scrolled to the top, which visibly eats into the top inset.
            // Bounds/frame notifications are coalesced above, so by the time this
            // runs `clipView.bounds` may already reflect that drift — compare
            // against the last known-good origin instead of the current bounds.
            let epsilon: CGFloat = 2
            let wasAtTop = lastStableClipOrigin.y < epsilon
            let wasAtLeft = lastStableClipOrigin.x < epsilon

            let clipWidth = clipView.bounds.width
            let newProseWidth = clipWidth - textView.textContainerInset.width * 2
            let widthChanged = newProseWidth > 0 && abs(container.proseWidth - newProseWidth) > 1
            if widthChanged {
                container.proseWidth = newProseWidth
            }
            textView.minSize = NSSize(width: clipWidth, height: 0)
            let neededWidth = max(clipWidth, container.size.width)
            if abs(textView.frame.width - neededWidth) > 1 {
                textView.frame.size.width = neededWidth
            }

            if widthChanged {
                var correctedOrigin = clipView.bounds.origin
                var needsCorrection = false
                if wasAtTop && clipView.bounds.minY > epsilon {
                    correctedOrigin.y = 0
                    needsCorrection = true
                }
                if wasAtLeft && clipView.bounds.minX > epsilon {
                    correctedOrigin.x = 0
                    needsCorrection = true
                }
                if needsCorrection {
                    clipView.scroll(to: correctedOrigin)
                    textView.enclosingScrollView?.reflectScrolledClipView(clipView)
                }
            }

            lastStableClipOrigin = clipView.bounds.origin
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
            updateTOC()

            // Re-run find if the find bar is visible (debounced to avoid per-keystroke search)
            if isFindBarVisible {
                pendingFindWorkItem?.cancel()
                let query = findState.searchText
                let item = DispatchWorkItem { [weak self] in
                    self?.performSearch(query: query)
                }
                pendingFindWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateCursorReveal()
        }

        // MARK: - List continuation on Return

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            return handleListContinuation(in: textView)
        }

        private static let orderedListLineRegex = try! NSRegularExpression(
            pattern: #"^(\s*)(\d+)([.)])\s+(.*)$"#
        )
        private static let unorderedListLineRegex = try! NSRegularExpression(
            pattern: #"^(\s*)([-*+])\s+(\[[ xX]\]\s+)?(.*)$"#
        )

        /// Continues a list when Return is pressed at the end of a list item
        /// (same marker, or the next number for ordered lists), and exits the
        /// list when Return is pressed on an already-empty item — matching
        /// the convention most list-aware editors use.
        private func handleListContinuation(in textView: NSTextView) -> Bool {
            let selRange = textView.selectedRange()
            guard selRange.length == 0 else { return false }

            let nsText = textView.string as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: selRange.location, length: 0))
            var lineContentEnd = NSMaxRange(lineRange)
            if lineContentEnd > lineRange.location, nsText.character(at: lineContentEnd - 1) == 10 {
                lineContentEnd -= 1
            }
            // Only take over Return at the end of the line's text — mid-line
            // Return should just split the text as usual.
            guard selRange.location == lineContentEnd else { return false }

            let line = nsText.substring(with: NSRange(location: lineRange.location, length: lineContentEnd - lineRange.location))
            let lineNS = line as NSString
            let fullLineRange = NSRange(location: 0, length: lineNS.length)

            if let match = Self.orderedListLineRegex.firstMatch(in: line, range: fullLineRange) {
                let indent = lineNS.substring(with: match.range(at: 1))
                guard let number = Int(lineNS.substring(with: match.range(at: 2))) else { return false }
                let delim = lineNS.substring(with: match.range(at: 3))
                let content = lineNS.substring(with: match.range(at: 4))

                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    removeMarker(textView: textView, lineStart: lineRange.location, lineContentEnd: lineContentEnd, indent: indent)
                } else {
                    textView.insertText("\n\(indent)\(number + 1)\(delim) ", replacementRange: selRange)
                }
                return true
            }

            if let match = Self.unorderedListLineRegex.firstMatch(in: line, range: fullLineRange) {
                let indent = lineNS.substring(with: match.range(at: 1))
                let bullet = lineNS.substring(with: match.range(at: 2))
                let hasCheckbox = match.range(at: 3).location != NSNotFound
                let content = lineNS.substring(with: match.range(at: 4))

                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    removeMarker(textView: textView, lineStart: lineRange.location, lineContentEnd: lineContentEnd, indent: indent)
                } else {
                    let newMarker = hasCheckbox ? "\(indent)\(bullet) [ ] " : "\(indent)\(bullet) "
                    textView.insertText("\n\(newMarker)", replacementRange: selRange)
                }
                return true
            }

            return false
        }

        private func removeMarker(textView: NSTextView, lineStart: Int, lineContentEnd: Int, indent: String) {
            textView.insertText(indent, replacementRange: NSRange(location: lineStart, length: lineContentEnd - lineStart))
        }

        // MARK: - Table of contents

        func updateTOC() {
            guard let tocModel = parent.tocModel else { return }
            let headings = markdownTextStorage?.lastStyleMap?.headings ?? []
            tocModel.items = headings.map {
                TableOfContentsModel.Item(range: $0.range, level: $0.level, title: $0.title)
            }
        }

        private func scrollToHeading(_ range: NSRange) {
            guard let textView else { return }
            let maxLen = (textView.string as NSString).length
            guard range.location <= maxLen else { return }
            let safeRange = NSRange(location: range.location, length: min(range.length, maxLen - range.location))
            textView.scrollRangeToVisible(safeRange)
            textView.setSelectedRange(NSRange(location: safeRange.location, length: 0))
            textView.window?.makeFirstResponder(textView)
        }

        // MARK: - Cursor-aware reveal

        private func updateCursorReveal() {
            guard let textView,
                  let layoutDelegate,
                  let styleMap = markdownTextStorage?.lastStyleMap
            else { return }

            let cursorPos = textView.selectedRange().location
            let oldActive = layoutDelegate.activeSpanRange

            // Find the element the cursor is in using binary search
            // (elements are sorted by fullRange.location from the AST walk)
            var newActive: NSRange?
            let elements = styleMap.elements
            var lo = 0, hi = elements.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                let el = elements[mid]
                if el.fullRange.location > cursorPos {
                    hi = mid - 1
                } else if NSMaxRange(el.fullRange) < cursorPos {
                    lo = mid + 1
                } else {
                    // cursorPos is within or at the end of this element
                    // Search nearby for the best match (innermost with delimiters)
                    // Walk backwards to find the first overlapping element
                    var start = mid
                    while start > 0 && elements[start - 1].fullRange.location + elements[start - 1].fullRange.length >= cursorPos {
                        start -= 1
                    }
                    // Walk forward through overlapping elements
                    for i in start..<elements.count {
                        let e = elements[i]
                        if e.fullRange.location > cursorPos { break }
                        if !e.delimiterRanges.isEmpty &&
                           (NSLocationInRange(cursorPos, e.fullRange) || cursorPos == NSMaxRange(e.fullRange)) {
                            newActive = e.fullRange
                            break
                        }
                    }
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

        // MARK: - Checkbox toggling

        func handleCheckboxClick(at charIndex: Int) -> Bool {
            guard let textView, let styleMap = markdownTextStorage?.lastStyleMap,
                  let checkbox = styleMap.checkboxes.first(where: { NSLocationInRange(charIndex, $0.range) })
            else { return false }

            let newBracket = checkbox.checked ? "[ ]" : "[x]"
            textView.window?.makeFirstResponder(textView)
            textView.insertText(newBracket, replacementRange: checkbox.range)
            return true
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
            guard url != watchedURL else { return }
            fileWatcher?.stop()
            watchedURL = url
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
                // Atomic writes replace the file (new inode), so the old
                // descriptor goes stale. Stop watching, then try to re-attach
                // after a short delay — the replacement file should exist by then.
                fileWatcher?.stop()
                watchedURL = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self else { return }
                    if FileManager.default.fileExists(atPath: url.path) {
                        self.startWatching(url: url)
                        self.handleExternalModification(url: url)
                    }
                    // If file truly deleted, we stay stopped
                }
            }
        }

        private func handleExternalModification(url: URL) {
            guard let newData = try? Data(contentsOf: url),
                  let newText = String(data: newData, encoding: .utf8)
            else { return }

            let doc = parent.document

            // See ExternalChangeResolver for the classification rationale (own
            // save echoing back through the watcher vs. a real external edit,
            // and whether local edits since the last confirmed save mean this
            // needs the conflict dialog rather than a silent merge).
            let resolution = ExternalChangeResolver.resolve(
                newText: newText,
                currentText: doc.text,
                lastConfirmedSavedText: doc.lastConfirmedSavedText,
                pendingSaveTexts: pendingSaveTexts
            )

            switch resolution {
            case .ignoreOwnEcho(let shouldMarkConfirmed):
                if shouldMarkConfirmed {
                    doc.markSaveConfirmed(newText)
                }
                pendingSaveTexts.remove(newText)
            case .ignoreMatchesCurrent:
                break
            case .conflict:
                presentConflictAlert(newText: newText, doc: doc)
            case .silentMerge:
                applyExternalText(newText, to: doc)
            }
        }

        private func presentConflictAlert(newText: String, doc: MarkdownDocument) {
            guard let window = textView?.window else { return }
            let textAtAlertTime = doc.text

            let alert = NSAlert()
            alert.messageText = "File Changed on Disk"
            alert.informativeText = """
                This file was modified outside the editor while you have unsaved changes here.

                Reload to load the external version — your current edits will be copied to the clipboard first, just in case. Keep Mine to discard the external version (it will be overwritten the next time you save).
                """
            alert.addButton(withTitle: "Reload")
            alert.addButton(withTitle: "Keep Mine")
            alert.alertStyle = .warning

            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn else { return }

                // Safety net: always copy what's about to be discarded, in case the
                // user needs to recover it manually.
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(doc.text, forType: .string)

                let userKeptTyping = doc.text != textAtAlertTime
                self.applyExternalText(newText, to: doc)

                if userKeptTyping {
                    self.notifyClipboardSafetyNet(window: window)
                }
            }
        }

        private func notifyClipboardSafetyNet(window: NSWindow) {
            let alert = NSAlert()
            alert.messageText = "Your Latest Edits Were Copied"
            alert.informativeText = "You kept typing while the file-changed dialog was open, so those edits were about to be discarded. They've been copied to the clipboard — paste them somewhere safe if you need them."
            alert.alertStyle = .informational
            alert.beginSheetModal(for: window)
        }

        /// Apply externally-loaded text without polluting the undo stack.
        private func applyExternalText(_ newText: String, to doc: MarkdownDocument) {
            doc.text = newText
            doc.markSaveConfirmed(newText)
            // Clear undo actions registered by the programmatic text replacement
            // so that canUndo only reflects real user edits.
            parent.undoManager?.removeAllActions()
            textView?.undoManager?.removeAllActions()

            // The merge above only updates our own app-level tracking
            // (`lastConfirmedSavedText`). SwiftUI's DocumentGroup/ReferenceFileDocument
            // machinery independently tracks the file's last-known-good revision via
            // AppKit's underlying NSDocument.fileModificationDate, and never sees this
            // out-of-band external read. Left alone, the NEXT real save — even one with
            // no further conflict in substance — trips AppKit's own built-in "document
            // changed by another application" alert (Save Anyway / Revert / Save As),
            // which bypasses our custom conflict dialog entirely since it's generated
            // deeper in the document architecture, and whose "Revert" option would
            // silently discard whatever the user types next. SwiftUI doesn't expose the
            // underlying NSDocument, but it still registers it with the shared
            // NSDocumentController under the standard file URL, so fetch it from there
            // and update its modification date to match what's now on disk.
            if let url = watchedURL ?? parent.fileURL {
                let nsDoc = NSDocumentController.shared.document(for: url)
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let modDate = attrs?[.modificationDate] as? Date
                if let nsDoc, let modDate {
                    nsDoc.fileModificationDate = modDate
                }
            }
        }

        // MARK: - Save verification

        private func scheduleSaveVerification(expecting text: String) {
            pendingSaveTexts.insert(text)
            verifySaveAfterDelay(0.4, expecting: text, attempt: 0)
        }

        private func verifySaveAfterDelay(_ delay: TimeInterval, expecting text: String, attempt: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.verifySave(expecting: text, attempt: attempt)
            }
        }

        private func verifySave(expecting text: String, attempt: Int) {
            // Already confirmed by another path (e.g. the file watcher's own-echo
            // check beat this timer to it) — nothing left to do.
            guard pendingSaveTexts.contains(text) else { return }
            guard let url = watchedURL ?? parent.fileURL else { return }

            let doc = parent.document
            guard let diskText = try? String(contentsOf: url, encoding: .utf8) else {
                retryOrFailSaveVerification(expecting: text, attempt: attempt)
                return
            }

            if diskText == text {
                doc.markSaveConfirmed(text)
                pendingSaveTexts.remove(text)
            } else if diskText == doc.text {
                // A newer save has already superseded this one — confirmed either way.
                doc.markSaveConfirmed(diskText)
                pendingSaveTexts.remove(text)
            } else {
                retryOrFailSaveVerification(expecting: text, attempt: attempt)
            }
        }

        private func retryOrFailSaveVerification(expecting text: String, attempt: Int) {
            let nextAttempt = attempt + 1
            if nextAttempt == 1 {
                verifySaveAfterDelay(1.0, expecting: text, attempt: nextAttempt)
            } else if nextAttempt == 2 {
                verifySaveAfterDelay(2.0, expecting: text, attempt: nextAttempt)
            } else {
                showSaveVerificationWarning()
                pendingSaveTexts.remove(text)
            }
        }

        private func showSaveVerificationWarning() {
            guard let window = textView?.window else { return }
            let alert = NSAlert()
            alert.messageText = "Save May Not Have Completed"
            alert.informativeText = "The last save doesn't appear to have reached disk. Your current text is still safely in the editor — copy it now as a backup before doing anything else."
            alert.addButton(withTitle: "Copy Text")
            alert.addButton(withTitle: "Dismiss")
            alert.alertStyle = .critical
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn, let self else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(self.parent.document.text, forType: .string)
            }
        }

        // MARK: - PDF export

        func observeExportToPDF() {
            exportObserver = NotificationCenter.default.addObserver(
                forName: .exportToPDF,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.textView?.window?.isKeyWindow == true else { return }
                self.exportToPDF()
            }
        }

        private func exportToPDF() {
            let text = parent.document.text
            let fileURL = parent.fileURL
            let baseURL = fileURL?.deletingLastPathComponent()

            let renderer = MarkdownHTMLRenderer(baseURL: baseURL)
            let html = renderer.fullDocument(markdown: text)
            let suggestedName = firstHeading(from: text)
                ?? fileURL?.deletingPathExtension().lastPathComponent
                ?? "Document"

            pdfExporter = MarkdownPDFExporter()
            pdfExporter?.export(html: html, baseURL: baseURL) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let data):
                    self.savePDF(data, suggestedName: suggestedName, near: fileURL)
                case .failure(let error):
                    self.showExportError(error)
                }
                self.pdfExporter = nil
            }
        }

        private func savePDF(_ data: Data, suggestedName: String, near sourceURL: URL?) {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = suggestedName + ".pdf"
            if let dir = sourceURL?.deletingLastPathComponent() {
                panel.directoryURL = dir
            }
            guard let window = textView?.window else { return }
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url)
                } catch {
                    self?.showExportError(error)
                }
            }
        }

        private func showExportError(_ error: Error) {
            guard let window = textView?.window else { return }
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window)
        }

        private func firstHeading(from text: String) -> String? {
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let str = line.trimmingCharacters(in: .whitespaces)
                if str.hasPrefix("# ") {
                    return String(str.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
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
