# MarkdownEditor

A native macOS markdown editor with hidden formatting. Syntax characters (`**`, `_`, `#`, `|`) disappear as you type, and styled text appears in their place. Think Bear or Typora, built with SwiftUI and TextKit 1.

## What it does

- **Hides delimiters** for bold, italic, headings, links, code, strikethrough, and tables
- **Shows them on demand** when you place your cursor inside a formatted span
- **Merges nested formatting** so `_text **bold**_` renders the inner word as bold-italic, not just bold
- **Renders tables** with hidden pipes and separator rows, auto-aligned columns (via kern padding), and bold monospace headers
- **Watches files** for external changes and prompts to reload
- **Supports dark mode** with automatic theme switching

## How formatting works

The raw markdown lives in an `NSTextStorage` subclass. On every edit, the app:

1. Parses the markdown into an AST using [swift-markdown](https://github.com/apple/swift-markdown)
2. Walks the AST to produce styled ranges and delimiter positions
3. Applies font/color attributes with trait merging (bold + italic = bold-italic)
4. Passes delimiter ranges to an `NSLayoutManagerDelegate` that sets `.null` glyph properties on those characters

The cursor reveal works by tracking which formatted span the cursor is in and temporarily restoring delimiter glyphs for that span.

## Tables

Tables get special treatment. Pipe characters and the separator row (`|---|---|`) are hidden. Columns stay aligned through `.kern` attributes on each cell's last character, computed from the maximum visual width per column. "Visual width" subtracts hidden inline delimiters so a cell containing `**bold**` (4 hidden chars) gets the right padding.

## Save behaviour

The app uses SwiftUI's `DocumentGroup` with `ReferenceFileDocument`. This gives you standard macOS document behaviour:

- **Auto-saves** periodically and when the window loses focus
- **Cmd+S** saves immediately
- **Closing with unsaved edits** triggers a save prompt
- **Undo/redo** works via the standard `UndoManager`

You won't lose edits by quitting without manually saving.

## Build

Requires macOS 14+ and Xcode with Swift Package Manager (swift-markdown is pulled automatically).

```
xcodebuild -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug -destination 'platform=macOS' build
```

The built app lands in DerivedData. To install:

```
cp -R ~/Library/Developer/Xcode/DerivedData/MarkdownEditor-*/Build/Products/Debug/MarkdownEditor.app /Applications/
```

## Project structure

| File | Role |
|------|------|
| `MarkdownEditorApp.swift` | App entry point, `DocumentGroup` setup |
| `MarkdownDocument.swift` | `ReferenceFileDocument` for file I/O |
| `MarkdownTextView.swift` | `NSViewRepresentable` bridge, keyboard shortcuts, cursor reveal |
| `MarkdownTextStorage.swift` | `NSTextStorage` subclass, attribute application, font trait merging |
| `MarkdownStyleMap.swift` | AST walker producing styled ranges and delimiter positions |
| `MarkdownLayoutManagerDelegate.swift` | Glyph hiding via `shouldGenerateGlyphs` |
| `MarkdownTheme.swift` | Fonts, colors, dark mode |
| `FileWatcher.swift` | `DispatchSource` file monitoring |
