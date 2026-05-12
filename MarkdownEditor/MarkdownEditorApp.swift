import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkdownEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { config in
            EditorView(document: config.document, fileURL: config.fileURL)
                .frame(minWidth: 500, minHeight: 400)
        }
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export as PDF…") {
                    NotificationCenter.default.post(name: .exportToPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}
