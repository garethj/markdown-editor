import AppKit
import UniformTypeIdentifiers
import WebKit

extension Notification.Name {
    static let exportToPDF = Notification.Name("MarkdownEditorExportToPDF")
}

final class MarkdownPDFExporter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completionHandler: ((Result<Data, Error>) -> Void)?
    private var tempURL: URL?

    func export(html: String, baseURL: URL?, completion: @escaping (Result<Data, Error>) -> Void) {
        precondition(Thread.isMainThread)
        completionHandler = completion

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 816, height: 1056))
        wv.navigationDelegate = self
        webView = wv

        wv.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let printInfo = NSPrintInfo()
        // A4: 210mm × 297mm in points (1pt = 1/72 in)
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
        printInfo.leftMargin   = 70.87   // 25mm
        printInfo.rightMargin  = 70.87
        printInfo.topMargin    = 56.69   // 20mm
        printInfo.bottomMargin = 56.69
        printInfo.horizontalPagination = .fit
        printInfo.isVerticallyCentered = false

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pdf")
        tempURL = url
        printInfo.jobDisposition = .save
        printInfo.dictionary().setValue(url as NSURL, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue)

        let op = webView.printOperation(with: printInfo)
        op.showsPrintPanel    = false
        op.showsProgressPanel = false

        guard let window = NSApplication.shared.keyWindow else {
            finish(.failure(NSError(
                domain: "MarkdownPDFExporter", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No key window for PDF export"])))
            return
        }

        // runModal processes the WebKit event loop so the web process can respond to
        // layout requests — op.run() deadlocks because it blocks the main thread.
        op.runModal(for: window, delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                    contextInfo: nil)
    }

    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let url = tempURL
        tempURL = nil
        // Callback arrives on a private AppKit thread; NSSavePanel must run on main.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let url else {
                self.finish(.failure(NSError(
                    domain: "MarkdownPDFExporter", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "PDF generation failed"])))
                return
            }
            if success, let data = try? Data(contentsOf: url) {
                try? FileManager.default.removeItem(at: url)
                self.finish(.success(data))
            } else {
                try? FileManager.default.removeItem(at: url)
                self.finish(.failure(NSError(
                    domain: "MarkdownPDFExporter", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "PDF generation failed"])))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Data, Error>) {
        completionHandler?(result)
        completionHandler = nil
        webView?.navigationDelegate = nil
        webView = nil
    }
}
