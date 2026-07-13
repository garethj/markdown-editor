import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown")
}

final class MarkdownDocument: ReferenceFileDocument {
    /// Above this size, `EditorView` withholds the real editor behind a
    /// warning until the user opts in — the markdown parse/style pipeline
    /// re-runs in full on every keystroke, so large files stay slow to edit
    /// even after they've opened.
    static let largeFileThresholdBytes = 512 * 1024

    @Published var text: String

    /// Content last *confirmed* (by direct read-back) to have reached disk.
    /// This is the source of truth for "are there unsaved changes" — it only
    /// advances once a write is verified, never optimistically at save time.
    @Published private(set) var lastConfirmedSavedText: String

    /// Size in bytes of the file as read from disk (0 for new/empty documents).
    let fileSizeBytes: Int

    /// Whether the user has opted to load a file above `largeFileThresholdBytes`.
    /// Starts `true` for files at or under the threshold.
    @Published var didConfirmLargeFileLoad: Bool

    /// Called synchronously from `snapshot(contentType:)` with the text about
    /// to be written, so observers can kick off save verification.
    var onWillSave: ((String) -> Void)?

    static var readableContentTypes: [UTType] { [.markdownText, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownText] }

    init(text: String = "") {
        self.text = text
        self.lastConfirmedSavedText = text
        self.fileSizeBytes = 0
        self.didConfirmLargeFileLoad = true
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
        self.lastConfirmedSavedText = string
        self.fileSizeBytes = data.count
        self.didConfirmLargeFileLoad = data.count <= Self.largeFileThresholdBytes
    }

    typealias Snapshot = String

    func snapshot(contentType: UTType) throws -> String {
        onWillSave?(text)
        return text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    /// Marks `text` as confirmed to have reached disk as of this content.
    func markSaveConfirmed(_ text: String) {
        lastConfirmedSavedText = text
    }
}
