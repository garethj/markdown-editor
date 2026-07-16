# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
xcodebuild -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug -destination 'platform=macOS' build
```

Built app lands in `~/Library/Developer/Xcode/DerivedData/MarkdownEditor-*/Build/Products/Debug/`. **Check for more than one `MarkdownEditor-*` DerivedData folder before installing** (`ls -la ~/Library/Developer/Xcode/DerivedData/ | grep -i markdown`) — a stale one left over from an old checkout/scheme change will match the same glob, and `cp -R` with multiple glob matches copies them in alphabetical order, so a stale folder sorting after the fresh one silently overwrites it with old code. If more than one exists, either delete the stale one or copy the specific fresh path explicitly instead of the wildcard. To install:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/MarkdownEditor-*/Build/Products/Debug/MarkdownEditor.app /Applications/
```

Requires macOS 14+ and Xcode. The `swift-markdown` (Apple) package is pulled automatically via SPM.

There are no unit tests.

**Debug builds split code into a dylib.** `Contents/MacOS/MarkdownEditor` in a Debug build is a thin stub; the actual compiled code lives in `Contents/MacOS/MarkdownEditor.debug.dylib` (Xcode's debug-dylib optimization). `strings`/`grep` on the main executable to confirm a change landed will find nothing — check the `.debug.dylib` instead.

## Architecture

This is a native macOS document-based app (SwiftUI `DocumentGroup`) using **TextKit 1** — not TextKit 2. This is intentional: the glyph-hiding mechanism (`NSLayoutManagerDelegate.shouldGenerateGlyphs`) is a TextKit 1 API.

### Data flow on every keystroke

```
NSTextView edit
  → MarkdownTextStorage.replaceCharacters
    → processEditing
      → applyMarkdownStyling (incremental: dirty region only)
        → MarkdownStyleMap(text:)   ← full AST re-parse (cmark, can't be incremental)
          → StyleWalker walks AST, produces [StyledElement]
        → apply NSAttributedString attributes for dirty region
        → MarkdownLayoutManagerDelegate.updateDelimiters(from:)  ← updates IndexSet
        → MarkdownTextContainer.tableLineRanges = styleMap.tableRegions
  → NSLayoutManager generates glyphs
    → MarkdownLayoutManagerDelegate.shouldGenerateGlyphs  ← sets .null for delimiters
```

### Glyph hiding

`MarkdownLayoutManagerDelegate` holds a `delimiterIndexSet: IndexSet`. During glyph generation it sets the `.null` property on any character whose index is in the set, making it invisible and zero-width. The `activeSpanRange` exempts the span the cursor is currently inside (so delimiters become visible when you move into them).

### Table layout

`MarkdownTextContainer` overrides `lineFragmentRect(forProposedRect:at:)` to return wider rects for table lines, enabling horizontal scrolling for wide tables while prose wraps at window width. Column alignment is achieved with `.kern` attributes on the last character of each cell, computed from max visual column widths (accounting for hidden inline delimiters).

### Cursor reveal

`updateCursorReveal()` (in `MarkdownTextView.Coordinator`) uses binary search over the sorted `styleMap.elements` array to find the `StyledElement` the cursor is in, then sets `layoutDelegate.activeSpanRange` and invalidates only that glyph range. This avoids full-document glyph invalidation on every cursor move.

### PDF export

`Cmd+Shift+E` posts `.exportToPDF`. `MarkdownHTMLRenderer` converts the markdown to HTML; `MarkdownPDFExporter` loads it in a hidden `WKWebView` and prints to a temp PDF file using `NSPrintOperation.runModal`. Note: `op.run()` deadlocks (blocks main thread, starving WebKit); `runModal` is required.

### Theme

`MarkdownTheme.shared` is a singleton rebuilt on dark-mode changes (`AppleInterfaceThemeChangedNotification`). All attribute dictionaries are cached via `rebuildCachedAttributes()` and should never be computed on the fly.

### Saving, autosave, and external-change detection

**`DocumentGroup`/`ReferenceFileDocument` autosaves in place automatically**, roughly 5+ seconds after the last edit — saves are not limited to explicit Cmd+S. Any logic that reasons about "has this been saved" must account for this.

`MarkdownDocument.lastConfirmedSavedText` is the source of truth for "has this content reached disk" — it only advances when content is actually read back and verified, never optimistically at save time. `MarkdownDocument.onWillSave` fires from `snapshot(contentType:)` (called synchronously, right before SwiftUI hands the content off to be written) so `MarkdownTextView.Coordinator` can schedule a direct read-back verification (`scheduleSaveVerification`/`verifySave`, with retries) independent of `FileWatcher` timing. The status bar's "Unsaved Changes" indicator is simply `document.text != document.lastConfirmedSavedText`.

`FileWatcher` is a raw `DispatchSourceFileSystemObject` on the file's inode (not `NSFilePresenter`), so it cannot itself distinguish the app's own atomic save (write-temp + rename, which unlinks the watched inode) from a real external edit — both fire identical `.deleted`/`.renamed` events. `Coordinator.handleExternalModification` tells them apart by content: if the file's new content matches `lastConfirmedSavedText` or is present in the in-flight `pendingSaveTexts` set, it's the app's own save echoing back and is ignored. Only a content mismatch against both is treated as a possible conflict, and only shows the "File Changed on Disk" dialog if `doc.text != doc.lastConfirmedSavedText` (real unsaved local edits) — **do not use `undoManager.canUndo` for this check**; a no-op undo action is registered on every keystroke purely for dirty-tracking (see `textDidChange`) and is never popped by an ordinary save, so `canUndo` stays permanently true after the first edit of a session and does not mean "unsaved since last save."

**`pendingSaveTexts` is a set, not a single slot** — overlapping saves are a real scenario (autosave fires, then a manual Cmd+S lands before the autosave's own disk-echo has round-tripped back through `FileWatcher`'s 300ms deleted/renamed reattach delay). A single shared slot would let the newer save's expected text overwrite the older one's, so the older save's echo would match neither `lastConfirmedSavedText` nor the (clobbered) expectation and get mistaken for a real external conflict — this was a real bug (fixed alongside this note). Each `scheduleSaveVerification`/`verifySave` retry chain closes over its own expected text and attempt count rather than reading shared mutable state, so concurrent chains can't stomp on each other.

**NSAlert sheets (`beginSheetModal`) are window-modal** — keystrokes sent to the underlying `NSTextView` while a sheet is open are dropped, not queued. The user cannot keep editing while the conflict dialog is showing. The clipboard safety-net in the "Reload" flow (copies `doc.text` before it's overwritten) still runs unconditionally as defense-in-depth, but don't assume concurrent typing during the sheet is a reachable scenario.

**There is a second, independent conflict-detection layer underneath all of the above, owned by AppKit itself, not by any of our code.** `DocumentGroup`/`ReferenceFileDocument` registers a real (private) `NSDocument` subclass with `NSDocumentController`, and that subclass tracks its own `fileModificationDate` via its `NSFileCoordinator`-backed read/write path — entirely independent of `MarkdownDocument.lastConfirmedSavedText`. Our `FileWatcher`-driven silent merge (`applyExternalText`) reads the external content out-of-band (`Data(contentsOf:)`, not through the document architecture) and updates only our own tracking. AppKit's document object never finds out, so the next real save — even one with no further conflict in substance — trips AppKit's own **built-in** "The document \"X\" could not be saved. The file has been changed by another application." alert (Save Anyway / Revert / Save As). This is a *completely different* dialog from our custom "File Changed on Disk" one (different code, different wording), fires from deeper in the document-save pipeline, and its "Revert" option silently discards whatever the user typed since the external edit — a real data-loss trap, not just a cosmetic double-prompt. Reproduced via: open → external edit (silently merged, no dialog) → type a local edit → Cmd+S → AppKit's own conflict alert appears.

Fixed in `applyExternalText` by fetching the underlying `NSDocument` via the public `NSDocumentController.shared.document(for: url)` (SwiftUI never exposes it directly, but it's still registered there under the standard file URL) and setting `.fileModificationDate` to the file's actual on-disk mtime immediately after the silent merge — this tells AppKit's own tracking "I've already seen this revision" before the user's next save, so it doesn't independently flag a conflict. Confirmed via a `NSDocument.save(_:)` action sent through the responder chain that this framework-level save only fires if the document is considered dirty (driven by the undo manager's change count) — an earlier attempt at this fix (triggering a redundant save right after `applyExternalText`) silently no-op'd because `parent.undoManager?.removeAllActions()` had already run moments before, leaving nothing to save; setting `fileModificationDate` directly sidesteps that entirely.

### Key files

| File | Role |
|------|------|
| `MarkdownTextStorage.swift` | Core edit pipeline; incremental dirty-region styling |
| `MarkdownStyleMap.swift` | AST walker; produces `[StyledElement]` with delimiter ranges |
| `MarkdownLayoutManagerDelegate.swift` | Glyph hiding via `shouldGenerateGlyphs` |
| `MarkdownTextContainer.swift` | Wide line fragments for tables; prose wrapping |
| `MarkdownTextView.swift` | SwiftUI bridge, cursor reveal, format actions, find bar, file watching, save verification |
| `MarkdownTheme.swift` | Fonts, colors, cached attribute dicts |
| `MarkdownDocument.swift` | `ReferenceFileDocument`; plain UTF-8 read/write; tracks `lastConfirmedSavedText` |
| `FileWatcher.swift` | Raw inode-level `DispatchSourceFileSystemObject` watch; no self-write suppression built in |
| `MarkdownPDFExporter.swift` | WKWebView → NSPrintOperation PDF pipeline |

## Important invariants

- **Always use `IndexSet` for delimiter lookups**, not `[NSRange]` linear scan — the delegate is called per-glyph.
- **Attribute dicts must come from `MarkdownTheme.shared`** cached properties, never allocate inline.
- **`applyMarkdownStyling` scopes attribute application to the dirty region** but always does a full AST parse (cmark limitation). Don't try to skip the full parse.
- **Delimiter invalidation happens inside `processEditing`** via `applyMarkdownStyling`. Don't add extra `invalidateGlyphs` calls in `textDidChange` — it causes scroll-to-bottom on every keystroke.
- The `NSTextView` has `isRichText = false` and smart substitutions disabled; keep it that way.
- **Don't use `undoManager.canUndo` as an "unsaved changes" proxy** — it's permanently true after the first edit of a session (see "Saving, autosave, and external-change detection" above). Use `document.text != document.lastConfirmedSavedText`.
