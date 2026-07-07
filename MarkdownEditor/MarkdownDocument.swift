import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown")
}

final class MarkdownDocument: ReferenceFileDocument {
    @Published var text: String

    /// Content last *confirmed* (by direct read-back) to have reached disk.
    /// This is the source of truth for "are there unsaved changes" — it only
    /// advances once a write is verified, never optimistically at save time.
    @Published private(set) var lastConfirmedSavedText: String

    /// Called synchronously from `snapshot(contentType:)` with the text about
    /// to be written, so observers can kick off save verification.
    var onWillSave: ((String) -> Void)?

    static var readableContentTypes: [UTType] { [.markdownText, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownText] }

    init(text: String = "") {
        self.text = text
        self.lastConfirmedSavedText = text
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
        self.lastConfirmedSavedText = string
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
