import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkdownEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { config in
            EditorView(document: config.document)
                .frame(minWidth: 500, minHeight: 400)
        }
        .defaultSize(width: 900, height: 700)
    }
}
