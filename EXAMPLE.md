This file demonstrates every markdown construct MarkdownEditor understands, so it doubles as a live feature showcase: open it in the app and see the hidden-formatting rendering in action, or read it as plain markdown to see the raw syntax each feature expects.

**Keep this file current.** Whenever a formatting feature is added, changed, or removed, update the matching section here in the same change — see the "Keeping EXAMPLE.md current" note in `CLAUDE.md`.

## Headings

ATX headings (`#` through `######`):

# Heading level 1
## Heading level 2
### Heading level 3
#### Heading level 4
##### Heading level 5
###### Heading level 6

Setext headings (underlined with `===` or `---`) also work, as long as a blank line separates them from whatever follows — without one, the underline attaches to the wrong line:

Setext Heading, Level 1
========================

Setext Heading, Level 2
------------------------

## Emphasis

This is **bold** text. This is `_italic_` text using underscores, or *italic* text using asterisks — asterisks also work mid-word (He*ll*o), unlike underscores, which CommonMark disallows mid-word (He_ll_o stays literal).

Nested emphasis merges correctly rather than just keeping whichever was applied last: _italic containing **nested bold**_ and **bold containing _nested italic_** both render the overlapping word as bold-italic. Three asterisks combine both from a single run: ***bold and italic together***.

## Strikethrough

~~Struck through with double tildes~~, or ~struck through with a single tilde~ — both are recognized.

## Highlight

A sentence with an ==highlighted phrase== in the middle. This is a MarkdownEditor-specific extension, not standard CommonMark.

## Inline code

Use `let x = 42` for a short snippet inline, styled in monospace.

## Code blocks

Fenced code blocks get monospace styling for their whole span:

```swift
func hello() -> String {
    return "Hello, World!"
}
```

## Links

[A link with visible text](https://apple.com) hides everything but the text itself. A bare URL auto-links without any bracket syntax at all: https://github.com/swiftlang/swift-markdown

## Blockquotes

> A single-line blockquote.

> A multi-line blockquote where every line has its own "> " marker,
> each colored the same as the accent color used for links and bullets.

> CommonMark "lazy continuation" also works: this line has no leading
"> " of its own, but is still part of the blockquote above it because
nothing else interrupts the paragraph.

## Lists

### Unordered, with nested depth

Bullet glyphs cycle by nesting depth — filled circle, hollow circle, filled diamond, hollow diamond:

- Top-level item
  - Nested one level
    - Nested two levels
      - Nested three levels

### Ordered

1. First item
2. Second item
3. Third item

### Task lists

Click a checkbox to toggle it — no need to select the line first:

- [ ] An unchecked task
- [x] A checked task

## Tables

Pipes and the separator row are hidden; columns stay aligned via kerning computed from each cell's *visual* width (hidden delimiters inside a cell don't count against its width):

| Name    | Role      | Status |
| ------- | --------- | ------ |
| Alice   | Engineer  | Active |
| Bob     | Designer  | Active |
| Charlie | **Lead**  | _Away_ |

## Formatting nested inside other constructs

Emphasis works inside list items — **bold with _nested italic_ inside a list item**.

## _An italicized heading_

A heading's own text can contain inline emphasis, independent of the heading's own hidden `#`/underline delimiter.
