# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git: commit freely, never push without being asked

This repo's `origin` remote is a **public** GitHub repository (`github.com/garethj/markdown-editor`). Commit locally as normal whenever the user asks for a commit — that's just local history, low-stakes. But **never run `git push` unless the user's current message explicitly asks for it**, even if a recent prior message in the same session asked for a push — that authorization doesn't carry forward to later commits, since a push makes the commit (and anything it contains) publicly visible immediately. If unsure whether "commit this" also means "and push it," ask, or default to commit-only and say so.

## Build

```bash
xcodebuild -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug -destination 'platform=macOS' build
```

Built app lands in `~/Library/Developer/Xcode/DerivedData/MarkdownEditor-*/Build/Products/Debug/`. **Check for more than one `MarkdownEditor-*` DerivedData folder before installing** (`ls -la ~/Library/Developer/Xcode/DerivedData/ | grep -i markdown`) — a stale one left over from an old checkout/scheme change will match the same glob, and `cp -R` with multiple glob matches copies them in alphabetical order, so a stale folder sorting after the fresh one silently overwrites it with old code. If more than one exists, either delete the stale one or copy the specific fresh path explicitly instead of the wildcard. To install:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/MarkdownEditor-*/Build/Products/Debug/MarkdownEditor.app /Applications/
```

Requires macOS 14+ and Xcode. The `swift-markdown` (Apple) package is pulled automatically via SPM.

**Reinstall to `/Applications` after code changes the user might check manually — don't wait to be asked.** This is a plain file copy (the command above), not disruptive like the interactive UI suite, so it doesn't need permission first. Do it as part of finishing any change that affects rendering, behavior, or anything else the user might open the app to look at (a bug fix, a new/changed formatting feature, a UI tweak) — skip it for pure test-only or documentation-only changes, where there's no compiled behavior to verify. The point is that `/Applications/MarkdownEditor.app` should never quietly be several commits behind the code, leaving the user debugging against a stale build without realizing it — this has actually happened (a font-merge fix looked "not working" because the installed app predated it by four days).

## Testing

Two test targets, at different tiers.

### Fast unit suite — `MarkdownEditorTests` — run before every commit

Hosted in the app (`TEST_HOST`/`@testable import MarkdownEditor`). Covers logic that's reachable without a live window/WindowServer session: `MarkdownStyleMap` parsing, `MarkdownTextStorage`'s incremental dirty-region styling, `MarkdownHTMLRenderer`, Return-key list continuation, `MarkdownDocument` save-state, and `ExternalChangeResolver` (the file-watcher conflict decision logic). Headless, runs in well under a second.

```bash
xcodebuild test -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS' -only-testing:MarkdownEditorTests
```

**Run this before every commit.** A failure means stop and investigate — don't commit past it, and don't skip the run because a change "looks safe." If a test fails and the fix isn't obvious, say so rather than silently loosening the assertion to make it pass.

**When fixing a bug or adding a feature, add or extend a test covering it**, if the logic is reachable without a live window (most parsing/styling/state logic is — check whether the equivalent existing test file already covers the area, e.g. a new inline-markdown construct belongs in `MarkdownStyleMapTests`, a new save/conflict edge case in `ExternalChangeResolverTests`). If the logic you just touched lives inline in `MarkdownTextView.Coordinator` and isn't reachable that way (private, or entangled with `NSTextView`/`NSDocument`/alerts), consider pulling the actual decision logic out into its own small internal type first — the way `ExternalChangeResolver.swift` was split out of `handleExternalModification` — rather than leaving it untestable. Don't force a test for logic that's genuinely only expressible as "does this render/scroll/look correct" — that's the other suite's job.

### Interactive UI suite — `MarkdownEditorUITests` — offer, never auto-run

A second target drives the real built app through XCUITest: a real window, real synthesized mouse clicks and keystrokes, a real `NSSavePanel` sheet. It exists specifically to cover what the fast suite structurally can't (see below). It is **not** part of the pre-commit command above — that command explicitly filters to `-only-testing:MarkdownEditorTests`, so the UI suite only runs when named explicitly (xcodebuild's `-only-testing` doesn't play well with `skipped` testables, so don't rely on scheme-level skipping — always use the `-only-testing:` filter shown above and never run `xcodebuild test` against this scheme with no filter):

```bash
xcodebuild test -project MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS' -only-testing:MarkdownEditorUITests
```

**This takes over the physical mouse and keyboard while it runs** — real windows come to the front, real clicks and keystrokes are synthesized on the actual display, a real save panel gets driven. It's genuinely disruptive to use the laptop for anything else while it runs.

**Current run time: ~2 minutes for 7 tests** (last measured 2026-07-18: `xcodebuild`'s own reported test time was 115s / 1m56s; wall-clock via `time` was 2m4s — use the larger, wall-clock figure when telling the user). Tell the user this figure (or your more recent one, see below) when you offer to run it, so they know how long to stay off the laptop — don't just say "a couple of minutes" without a number.

**Keep this figure current.** Whenever you add, remove, or meaningfully change a test in `MarkdownEditorUITests` (a new test class/method, a change to sleep/timeout durations, a new save-panel round trip, etc.), re-run the full suite once with `time` wrapped around the command above, and update the figure in this paragraph to match — both the test count and the duration. Don't leave a stale number here; a wrong estimate defeats the point of telling the user how long to stay away.

**Offer to run it — don't run it unprompted, and don't skip offering.** After a change that touches anything in the "what this covers" list below (glyph/cursor rendering, window/scroll behavior, `FileWatcher`/external-edit/conflict handling, PDF export, checkbox or link click hit-testing), tell the user what changed, state the current run-time estimate, and ask whether they'd like the interactive suite run now. Say plainly that it will take over the mouse and keyboard and that they should stop using the laptop (or at least stay off this display) until it finishes or they interrupt it. Wait for explicit go-ahead — a prior "yes" for one run doesn't authorize the next one. If they decline or don't respond, don't nag again for the same change; the fast suite plus a manual look is an acceptable fallback for that commit. Changes that only touch parsing/state logic already covered by the fast suite don't need this offer.

If a UI test fails, don't assume it's the test's fault (screen-recording/accessibility permissions, timing, an actual regression are all plausible) — investigate before loosening an assertion or increasing a timeout just to make it pass.

**Never leave a real project document open in a manually launched `MarkdownEditor.app`, and never force-`kill` it — always quit it cleanly (Cmd+Q, or `NSRunningApplication.terminate()`), and close its window (Cmd+W) first if you can.** Two compounding traps here, both hit in the same incident:
1. `XCUIApplication().launch()` activates the existing running instance of the same bundle ID rather than spawning an isolated one if one is already up, so a manually opened window is still frontmost and receiving keystrokes when a test's synthesized typing fires.
2. Worse, and less obvious: macOS persists per-app window-restoration state, and an *unclean* exit (a force `kill`, not a graceful quit) leaves that state pointing at whatever was open — so *every subsequent* `app.launch()`, even with zero other instances running and even in a completely fresh test process, silently **restores that same stale document window** instead of a blank one. `UITestSupport.launchWithFreshDocument`'s existence check only confirms *some* `MarkdownEditorTextView` exists, not that it's a blank document, so it happily proceeds to type test content into whatever got restored.

This actually happened: a manual GUI-verification pass opened `EXAMPLE.md`, was force-killed instead of cleanly quit, and from that point every UI-suite run — even after confirming via `ps aux` that no instance was running — kept reopening and retyping test content into that same real file, corrupting it under `git diff` twice in a row before the actual mechanism was understood. Recovery: quit the app via a clean Cmd+Q with no windows open (close any restored window with Cmd+W first) to overwrite the stale restoration state with "no windows" — verify by relaunching once and confirming a blank/picker window appears, not the old document. If corruption happens again: `git diff` the working tree immediately and restore by hand (not a blind `git checkout`, since that would also discard any of your own uncommitted legitimate edits mixed into the same file).

**New files added to `MarkdownEditorUITests` (or `MarkdownEditorTests`) must be registered in `project.pbxproj` by hand** — this project does not use Xcode 16's synchronized-folder groups (`PBXFileSystemSynchronizedRootGroup`), so a `Write`-created `.swift` file is invisible to the build system until it's added as a `PBXBuildFile` + `PBXFileReference` + a line in the target's group and `Sources` build phase (four edits — grep the existing entries for a sibling test file, e.g. `CheckboxUITests.swift`, and mirror all four for the new one, incrementing whatever ID numbering scheme is in use). Skipping this doesn't error — `build-for-testing` silently succeeds either way — it just means the new test never actually runs, which is easy to miss since "TEST BUILD SUCCEEDED" gives no indication a file was excluded. Verify a new test actually ran (not just compiled) by checking the executed test count/names in the output, not just build success.

**Reach for this suite before ad hoc GUI automation.** For any "does clicking X visually reveal/change Y" verification question, write or extend a test here using the established patterns (`CheckboxUITests`' `textView.coordinate(withNormalizedOffset:).withOffset(...)` for a real click at a screen point, `LayoutUITests`' `PixelSample.regionDifference` for screenshot-diffing a specific region, `UITestSupport.pasteText` for inserting content without O(n²) keystroke cost) rather than driving the real app via `osascript`/System Events. The latter's screen-coordinate math is fragile in ways this project's own XCUITest helpers already solve — real point-precision clicks resolved from the live accessibility tree, without hand-computing retina/logical-point scale factors from a screenshot.

**What the UI suite covers:**
- `LayoutUITests` — scroll position staying put while editing near the top of a long document (regression class for "scroll-to-bottom on every keystroke"), via coarse region-based screenshot comparison.
- `CheckboxUITests` — real mouse-click hit-testing on task-list checkboxes, through an actual click at a screen point rather than calling the handler with a given character index.
- `ExternalChangeUITests` — the real `FileWatcher` → merge/conflict path end-to-end: an actual external process writing the file while the app has it open, the real `NSAlert` conflict sheet, "Keep Mine," and confirming undo doesn't revert a silent merge.
- `PDFExportUITests` — the WKWebView → `NSPrintOperation` pipeline actually completing (regression guard for the documented `op.run()` deadlock trap) and producing a real, non-empty, valid PDF.
- `TableCellFormattingUITests` — cursor-reveal of nested bold/italic delimiters inside a table cell, via typed content + keyboard-only cursor movement (no absolute screen-point math) + region screenshot diff.

A window-resize-reflow test (dragging the window border and checking the text view reflows) was attempted but dropped — synthesizing a reliable window-border drag via XCUITest proved too unreliable, especially against a window restored zoomed/maximized from a prior session (five different drag techniques all produced zero measured size change). If you want to revisit this, expect to spend real iteration time on it; it's a known-hard corner of macOS UI testing, not a quick fix.

**Still not covered by either suite:**
- Window resize reflowing text/prose width — attempted, dropped for reliability reasons (see above). Needs either a better drag technique or a non-drag way to verify reflow (e.g. asserting on `MarkdownTextContainer`'s wide-line-fragment behavior for tables directly, without touching the window).
- Pixel-perfect visual/theme correctness — colors, fonts, checkbox glyph shape, dark-mode appearance. `LayoutUITests`' scroll-stability check does coarse region-based screenshot comparison (detects "did the content silently move," not "does it look right"). Needs human visual judgment, not a pass/fail gate.
- Cmd+click opening a URL in the real default browser — intentionally not automated, since it would actually open a browser tab during a test run.
- AppKit document-conflict interactions beyond the specific paths `ExternalChangeUITests` drives (e.g. what the *other*, AppKit-native "changed by another application" alert does after a "Keep Mine" resolution).
- Performance/memory regressions.
- Bugs that only emerge from a long chained sequence of real edits or several features interacting live (TOC sync during an external merge, find-bar state during reload).

For that remaining class, the fallback is manually driving the built app or asking the user to check visually — not a test.

**Debug builds split code into a dylib.** `Contents/MacOS/MarkdownEditor` in a Debug build is a thin stub; the actual compiled code lives in `Contents/MacOS/MarkdownEditor.debug.dylib` (Xcode's debug-dylib optimization). `strings`/`grep` on the main executable to confirm a change landed will find nothing — check the `.debug.dylib` instead.

## Keeping EXAMPLE.md current

`EXAMPLE.md` (repo root) is a live showcase of every markdown construct the app understands — a demo file for humans to open in the app and see hidden-formatting rendering in action, not a test. **Whenever you add, change, or remove a formatting feature** (a new construct `MarkdownStyleMap` understands, a change to how an existing one renders, a removed feature), update the matching section of `EXAMPLE.md` in the same change. Don't let it silently drift out of sync with what the app actually does — a demo file that lies about the feature set is worse than no demo file. If you're unsure whether a change is "formatting-feature-shaped" enough to warrant an update, err toward updating it.

## Keeping README.md current

`README.md` (repo root) is this project's GitHub landing page — the first (often only) thing a human sees before deciding whether to look further. It's a broader surface than `EXAMPLE.md`: not just formatting constructs, but the feature list, architecture summary, save/conflict behavior, build/install commands, test commands, and the project-structure file table. **Whenever a change would make any of those sections inaccurate** — a new user-facing feature (menu item, keyboard shortcut, toolbar button, sidebar), a changed build/test invocation, a new or renamed/removed source file worth listing, a materially changed save or conflict-handling behavior — update the matching section of `README.md` in the same change, the same way `EXAMPLE.md` gets updated for formatting features. This repo went 63 commits with a README frozen at its initial state before this rule was added (2026-07-21), silently missing tables, find, PDF export, the TOC sidebar, checkboxes, and external-change conflict handling entirely — don't let it drift back into that state. If unsure whether a change is README-shaped, err toward updating it.

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

### Delimiter visibility: hide vs. colorize

When adding styling for a new markdown construct, decide up front whether its delimiter characters carry real information or are pure syntax noise — this determines hide-vs-colorize, and getting it backwards is an easy way to accidentally discard something the user's source actually says:

- **Hide it** (add to `delimiterRanges`, per "Glyph hiding" above) when the character has zero reading value once the surrounding styling already signals the same thing — nobody needs to see the literal `**`/`_`/`` ` `` to know something's bold/italic/code, and ATX heading `#` is redundant once font size signals the level.
- **Keep it visible, recolored to the accent color** (`MarkdownTheme.shared.linkColor`, the same accent used for links) when the character *is* the information, or losing it would lose something the source actually distinguishes — a blockquote's `>`, a table's pipes and separator row, a Setext heading's `===`/`---` (the only thing distinguishing an H1 from an H2 in that syntax), a thematic break's `---`/`***`/`___` (the whole line *is* the marker), and an unordered list's bullet character itself (CommonMark treats a change of marker — `-` vs `*` vs `+` — as starting a new list, so replacing it with an app-invented shape would erase that distinction). Checkboxes follow the same rule at one remove: `[ ]`/`[x]` stays as literal bracket text, just recolored/dimmed, rather than being swapped for a custom glyph.

Concretely: append a second `StyledElement` for just the marker's sub-range, applied *after* the element covering the construct's full range, with attributes that set `.foregroundColor` only (no `.font`) — `backingStore.addAttributes` merges rather than replaces, so the marker inherits whatever font the base element already set (e.g. a Setext underline naturally staying at the heading's own size) and only the color changes. See `visitBlockQuote`/`blockQuoteMarkerAttributes`, `visitTable`/`tablePipeAttributes`, or the Setext branch of `visitHeading`/`headingUnderlineAttributes` in `MarkdownStyleMap.swift` for the pattern.

This project got this wrong once already: list bullets used to be hidden and replaced with a depth-cycling substitute glyph (●/○/◆/◇) via a dedicated `NSLayoutManagerDelegate` glyph-substitution mechanism — which silently broke when two of those Unicode characters turned out to have no glyph in `.AppleSystemUIFont` at the bullet's point size (the substitution no-opped, so the literal `-` drew instead, undetected until a screenshot caught it). Switching to literal-marker-recolored fixed the bug *and* removed the entire glyph-substitution subsystem, since bullets were its only caller.

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
