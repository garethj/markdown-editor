import Foundation

/// Pure decision logic for handling a `FileWatcher` change event, split out of
/// `MarkdownTextView.Coordinator.handleExternalModification` so it can be unit
/// tested without any AppKit view/document machinery. See CLAUDE.md's "Saving,
/// autosave, and external-change detection" section for the full rationale.
enum ExternalChangeResolution: Equatable {
    /// The disk content is our own save (confirmed or still in flight) echoing
    /// back through the watcher. `shouldMarkConfirmed` is true when this text
    /// wasn't already `lastConfirmedSavedText` (i.e. it was recognized only via
    /// `pendingSaveTexts`), meaning the caller should call `markSaveConfirmed`.
    case ignoreOwnEcho(shouldMarkConfirmed: Bool)
    /// The disk content already matches the in-memory document (e.g. macOS
    /// auto-save on focus loss writing back what's already there) — nothing to do.
    case ignoreMatchesCurrent
    /// No local edits since the last confirmed save — safe to merge silently.
    case silentMerge
    /// Local edits exist that haven't reached disk — surface the conflict dialog.
    case conflict
}

enum ExternalChangeResolver {
    static func resolve(
        newText: String,
        currentText: String,
        lastConfirmedSavedText: String,
        pendingSaveTexts: Set<String>
    ) -> ExternalChangeResolution {
        if newText == lastConfirmedSavedText || pendingSaveTexts.contains(newText) {
            return .ignoreOwnEcho(shouldMarkConfirmed: newText != lastConfirmedSavedText)
        }

        if newText == currentText {
            return .ignoreMatchesCurrent
        }

        let hasLocalChanges = currentText != lastConfirmedSavedText
        return hasLocalChanges ? .conflict : .silentMerge
    }
}
