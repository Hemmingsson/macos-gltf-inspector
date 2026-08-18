import Cocoa
import QuickLookUI
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var stagingDir: URL?
    private var continuation: CheckedContinuation<Void, Error>?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        guard
            let htmlURL = Bundle.main.url(forResource: "viewer", withExtension: "html"),
            let jsURL = Bundle.main.url(forResource: "model-viewer.min", withExtension: "js")
        else {
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let glbData = GLBMaterialConverter.prepareForWebPreview(try Data(contentsOf: url))

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        stagingDir = staging
        try FileManager.default.copyItem(at: htmlURL, to: staging.appendingPathComponent("viewer.html"))
        try FileManager.default.copyItem(at: jsURL, to: staging.appendingPathComponent("model-viewer.min.js"))
        try glbData.write(to: staging.appendingPathComponent("model.glb"))

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            let page = staging.appendingPathComponent("viewer.html")
            webView.loadFileURL(page, allowingReadAccessTo: staging)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.getElementById('viewer').src = 'model.glb'") { [weak self] _, _ in
            self?.continuation?.resume()
            self?.continuation = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
