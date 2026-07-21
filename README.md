# MarkdownEditor

A native macOS markdown editor with hidden formatting. Syntax characters disappear as you type and styled text appears in their place — bold looks bold, headings look big, links look like links — while the file on disk stays plain, portable markdown. Built natively with SwiftUI and TextKit 1.

See `EXAMPLE.md` for a live showcase of every construct below — open it in the app to see the hidden-formatting rendering in action, or read it as plain text to see the raw syntax each feature expects.

## What it does

- **Hides pure-syntax delimiters** — `**`/`_`/`~~` for bold, italic, and strikethrough, the ATX `#` for headings, code fences, and link brackets/URLs — so only the styled result shows
- **Keeps meaningful delimiters visible**, recolored in an accent color rather than hidden: a blockquote's `>`, a table's pipes and separator row, a Setext heading's `===`/`---` underline, a thematic break's `---`/`***`/`___`, and a list item's bullet character (CommonMark treats a change of marker as starting a new list, so the app preserves `-` vs `*` vs `+` rather than replacing them with a generic glyph)
- **Reveals hidden delimiters on demand** when you place the cursor inside a formatted span
- **Merges nested formatting** correctly, so `_text **bold**_` renders the inner word as bold-italic rather than just whichever style was applied last
- **Supports headings** (ATX `#`–`######` and Setext `===`/`---`), emphasis, strikethrough, a `==highlight==` extension, inline and fenced code, links (bracketed and bare autolinks), blockquotes (including CommonMark lazy continuation), thematic breaks, and ordered/unordered/task lists with nested depth and hanging-indented wrapped lines
- **Task lists with clickable checkboxes** — click `[ ]`/`[x]` directly to toggle, no need to select the line
- **Renders tables** with hidden separator rows, auto-aligned columns via kerning (computed from each cell's visual width, ignoring hidden inline delimiters), and horizontal scrolling for wide tables while prose still wraps at the window edge
- **Table of contents sidebar**, toggleable from the toolbar, built from the document's headings and kept in sync as you type
- **Find bar** (Cmd+F) for in-document search
- **Exports to PDF** (Cmd+Shift+E) via a headless WebKit render of the rendered HTML
- **Status bar** with live word count, character count, and estimated reading time
- **Watches the file on disk** for external changes and offers to reload, with conflict handling for edits made both in the app and externally since the last save
- **Warns before opening very large files** (>512KB), since every keystroke re-parses the whole document
- **Supports dark mode** with automatic theme switching

## How formatting works

The raw markdown lives in an `NSTextStorage` subclass. On every edit, the app:

1. Parses the markdown into an AST using [swift-markdown](https://github.com/apple/swift-markdown) (a full re-parse each time — this is the one part that isn't incremental)
2. Walks the AST to produce styled ranges and delimiter positions
3. Applies font/color attributes with trait merging (bold + italic = bold-italic), scoped to the dirty region only
4. Passes delimiter ranges to an `NSLayoutManagerDelegate` that sets the `.null` glyph property on those characters, making them invisible and zero-width

The cursor reveal works by binary-searching the styled ranges to find which formatted span the cursor is in, then temporarily restoring that span's delimiter glyphs.

## Tables

Tables get special treatment. The separator row (`|---|---|`) is hidden entirely; the pipe characters stay visible, recolored in the accent color, so table structure still reads at a glance. Columns stay aligned through `.kern` attributes on each cell's last character, computed from the maximum visual width per column — "visual width" subtracts hidden inline delimiters, so a cell containing `**bold**` (4 hidden characters) still gets the right padding. A custom text container widens table line fragments so wide tables scroll horizontally instead of wrapping, while ordinary prose keeps wrapping at the window edge.

## Save behaviour

The app uses SwiftUI's `DocumentGroup` with `ReferenceFileDocument`, which autosaves periodically and on focus loss, in addition to Cmd+S. On top of that:

- A direct read-back verification confirms saved content actually reached disk, rather than trusting the save call optimistically
- A file-system watcher detects changes made by *other* processes and distinguishes them from the app's own save (by content, not just by file event) before deciding whether to silently merge or prompt with a "File Changed on Disk" dialog
- AppKit's own independent, framework-level conflict tracking is kept in sync with these external merges, so a later save doesn't unexpectedly trigger a second, different "file has been changed by another application" alert
- Undo/redo works via the standard `UndoManager`

You won't lose edits by quitting without manually saving.

## Build

Requires macOS 14+ and Xcode. The `swift-markdown` package is pulled automatically via Swift Package Manager.

```bash
xcodebuild -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug -destination 'platform=macOS' build
```

The built app lands in DerivedData. To install:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/MarkdownEditor-*/Build/Products/Debug/MarkdownEditor.app /Applications/
```

## Testing

Two test targets, at different tiers:

- **`MarkdownEditorTests`** — a fast, headless unit suite covering markdown parsing/styling, incremental dirty-region updates, HTML rendering, list-continuation behavior, document save-state, and external-change conflict logic. Runs in well under a second:

  ```bash
  xcodebuild test -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS' -only-testing:MarkdownEditorTests
  ```

- **`MarkdownEditorUITests`** — a slower XCUITest suite that drives the real built app end-to-end (real clicks, keystrokes, save panels) to cover what the unit suite structurally can't: glyph/cursor rendering, scroll behavior, file-watcher conflict dialogs, PDF export, and checkbox hit-testing. Takes over the physical mouse and keyboard while it runs:

  ```bash
  xcodebuild test -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS' -only-testing:MarkdownEditorUITests
  ```

## Project structure

| File | Role |
|------|------|
| `MarkdownEditorApp.swift` | App entry point, `DocumentGroup` and menu setup |
| `MarkdownDocument.swift` | `ReferenceFileDocument` for file I/O, save-state tracking, large-file handling |
| `MarkdownTextView.swift` | SwiftUI bridge (`EditorView`/`NSViewRepresentable`), keyboard shortcuts, cursor reveal, checkbox toggling, list continuation |
| `MarkdownTextStorage.swift` | `NSTextStorage` subclass; incremental dirty-region attribute application |
| `MarkdownStyleMap.swift` | AST walker producing styled ranges and delimiter positions |
| `MarkdownLayoutManagerDelegate.swift` | Glyph hiding via `shouldGenerateGlyphs` |
| `MarkdownLayoutManager.swift` | `NSLayoutManager` subclass |
| `MarkdownTextContainer.swift` | Wide line fragments for tables; prose wrapping |
| `MarkdownTheme.swift` | Fonts, colors, cached attribute dictionaries, dark mode |
| `FileWatcher.swift` | Raw `DispatchSource` inode-level file monitoring |
| `ExternalChangeResolver.swift` | Decision logic for merging vs. prompting on external file changes |
| `TableOfContentsView.swift` | Heading sidebar, kept in sync with the document |
| `TableOverlayView.swift` | Table-specific rendering overlay |
| `FindBarView.swift` / `FindState.swift` | In-document find UI and state |
| `MarkdownHTMLRenderer.swift` | Markdown → HTML conversion, used for PDF export |
| `MarkdownPDFExporter.swift` | WKWebView → `NSPrintOperation` PDF export pipeline |

## License

MIT — see `LICENSE`.
