# Performance Improvements for Markdown Editor

## Context
The editor feels sluggish during normal use. The root cause is that **every keystroke triggers a full-document re-parse, full-document restyle, and full-document regex scan** — plus several O(n) or O(n×m) operations in the glyph hiding and overlay systems. For small documents this is tolerable; as documents grow, it compounds.

## Proposed Improvements (prioritised)

### 1. ~~Use a bitmap (IndexSet) for delimiter lookups instead of linear scan~~
**Impact: HIGH | Effort: LOW**

`shouldHideCharacter(at:)` does a linear scan of all delimiter ranges for every glyph. Replace `[NSRange]` with an `IndexSet` for O(1) `contains()` checks.

**Files:** `MarkdownLayoutManagerDelegate.swift` (lines 4, 48–60), `MarkdownTextStorage.swift` (delimiter update)

---

### 2. Short-circuit table overlay updates when cursor hasn't changed table context
**Impact: HIGH | Effort: LOW**

`updateTableOverlays()` destroys and rebuilds all overlays on every selection change. Add a guard: if cursor is in the same table (or same non-table region) as before, skip the work.

**Files:** `MarkdownTextView.swift` (lines 487–490, 536–602)

---

### 3. Cache theme attribute dictionaries
**Impact: MEDIUM | Effort: LOW**

All `MarkdownTheme` attribute dictionaries (`defaultAttributes`, `boldAttributes`, heading styles, paragraph styles) are computed properties that allocate new dictionaries on every access. Make them lazy stored properties, rebuilt only on theme change.

**Files:** `MarkdownTheme.swift` (lines 113–201)

---

### 4. Binary search for cursor reveal element lookup
**Impact: MEDIUM | Effort: LOW**

`updateCursorReveal()` linearly scans all styled elements. Since elements are sorted by position, use binary search on `fullRange.location` to find the relevant element in O(log n).

**Files:** `MarkdownTextView.swift` (lines 494–529)

---

### 5. Debounce status bar word/character count
**Impact: LOW–MEDIUM | Effort: LOW**

`StatusBarView` recomputes word count (O(n) string scan) on every keystroke. Debounce to ~300ms or compute on a background thread.

**Files:** `MarkdownTextView.swift` (lines 21–43)

---

### 6. Scope regex matching (URLs, highlights) to edited region
**Impact: MEDIUM | Effort: MEDIUM**

`bareURLRegex` and `highlightRegex` scan the entire document on every keystroke. Scope the match range to the edited paragraph (expanded to line boundaries for URL continuity).

**Files:** `MarkdownTextStorage.swift` (lines 143–198)

---

### 7. Avoid double `positionOverlay()` calls
**Impact: LOW | Effort: LOW**

`resizeTableOverlays()` and `updateTableOverlays()` both call `positionOverlay()` twice per overlay. Remove the redundant first call.

**Files:** `MarkdownTextView.swift` (lines 597–600, 678–683)

---

### 8. Deduplicate clip-view scroll/frame observers
**Impact: LOW | Effort: LOW**

Both `boundsDidChangeNotification` and `frameDidChangeNotification` trigger overlay repositioning — often firing together. Coalesce with a single `DispatchQueue.main.async` guard flag.

**Files:** `MarkdownTextView.swift` (lines 384–426)

---

### 9. Debounce find bar search
**Impact: LOW | Effort: LOW**

Search fires on every character typed in the find field, scanning the full document. Add a 200ms debounce.

**Files:** `MarkdownTextView.swift` (lines 860–900), `FindBarView.swift` (lines 169–171)

---

### 10. Cache table overlay grid path
**Impact: LOW | Effort: LOW**

`TableOverlayView.draw()` reconstructs the grid `NSBezierPath` on every draw call. Cache it and only rebuild on size change.

**Files:** `TableOverlayView.swift` (lines 166–205)

---

### 11. Incremental/dirty-region styling — only restyle the edited paragraph
**Impact: HIGH | Effort: HIGH**

Currently `applyMarkdownStyling()` resets attributes on the entire document, re-parses the full AST, and re-applies every style element on every keystroke. Instead:
- Track the `editedRange` from `processEditing()`
- Expand it to enclosing block boundaries (paragraph/list/table)
- Only reset and restyle that region
- Full re-parse of the AST is still needed (cmark doesn't support incremental), but attribute application can be scoped

**Files:** `MarkdownTextStorage.swift` (lines 40–93), `MarkdownStyleMap.swift`
