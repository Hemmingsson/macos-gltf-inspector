import AppKit
import CoreGraphics
import Foundation
import WebKit

/// Renders one glTF file to a still image through WebGL in an off-screen `WKWebView`.
///
/// Spike counterpart to `StillRenderer` — same shape (construct, `capture()`, get a `CGImage`)
/// so the thumbnail path can swap between them on one flag.
///
/// The web view is deliberately **never added to a window**. That is the property under test:
/// `QLThumbnailProvider` is a non-UI extension, so if WebGL only works when the view is
/// window-hosted, this whole direction is dead. Pixels come back via `canvas.toDataURL()`
/// rather than `WKWebView.takeSnapshot`, because reading the WebGL drawing buffer from
/// JavaScript does not depend on the view being layer-backed or on screen.
@MainActor
final class WebStillRenderer: NSObject {
    enum Failure: LocalizedError {
        /// The page never sent a message. Almost always a WebContent that could not start.
        case timedOut
        /// WebContent died — the expected shape of a sandbox denial.
        case webContentTerminated
        case navigationFailed(String)
        /// The page reported a failure, tagged with the stage it reached.
        case pageError(stage: String, message: String)
        case missingRendererBundle
        case undecodableImage

        var errorDescription: String? {
            switch self {
            case .timedOut:
                "Web renderer did not respond"
            case .webContentTerminated:
                "Web content process terminated (sandbox denial?)"
            case .navigationFailed(let message):
                "Web renderer navigation failed: \(message)"
            case .pageError(let stage, let message):
                "Web renderer failed at \(stage): \(message)"
            case .missingRendererBundle:
                "web-renderer resources missing from bundle"
            case .undecodableImage:
                "Web renderer returned an image that could not be decoded"
            }
        }
    }

    struct Result {
        var image: CGImage
        var triangles: Int
        var drawCalls: Int
        /// Milliseconds spent inside the page, from module import to PNG encode.
        var pageMilliseconds: Int
    }

    private static let scheme = "gltf-inspector"
    private static let messageName = "still"

    private let modelURL: URL
    private let pixelSize: Int
    private let timeout: Duration

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Result, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(model: URL, pixelSize: Int, timeout: Duration = .seconds(10)) {
        self.modelURL = model
        self.pixelSize = max(64, pixelSize)
        self.timeout = timeout
    }

    func capture() async throws -> Result {
        guard let rendererRoot = Self.rendererRoot else { throw Failure.missingRendererBundle }

        let configuration = WKWebViewConfiguration()
        // The extension has no business persisting caches into its container.
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            LocalResourceHandler(rendererRoot: rendererRoot, model: modelURL),
            forURLScheme: Self.scheme
        )
        configuration.userContentController.add(self, name: Self.messageName)

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            configuration: configuration
        )
        webView.navigationDelegate = self
        self.webView = webView

        var components = URLComponents(string: "\(Self.scheme):///renderer/thumb.html")!
        components.queryItems = [
            URLQueryItem(name: "size", value: String(pixelSize)),
            URLQueryItem(name: "model", value: "\(Self.scheme):///model"),
        ]

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [timeout] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await self.finish(.failure(Failure.timedOut))
            }
            webView.load(URLRequest(url: components.url!))
        }
    }

    /// Resolves exactly once; later calls are dropped. Several paths race to report failure —
    /// timeout, WebContent death, and the page's own error handler can all fire for one cause.
    private func finish(_ outcome: Swift.Result<Result, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.messageName)
        webView?.navigationDelegate = nil
        webView = nil

        switch outcome {
        case .success(let result):
            AppLog.info(
                AppLog.webThumb,
                "web still ok \(modelURL.lastPathComponent) \(result.pageMilliseconds)ms "
                    + "tris=\(result.triangles) calls=\(result.drawCalls)"
            )
        case .failure(let error):
            AppLog.error(
                AppLog.webThumb,
                "web still failed \(modelURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
        continuation.resume(with: outcome)
    }

    /// `Vendor/web-renderer` lands in the bundle as a folder reference, so the nested
    /// `addons/…` layout the ES module imports rely on is preserved.
    private static var rendererRoot: URL? {
        Bundle(for: WebStillRenderer.self).url(forResource: "web-renderer", withExtension: nil)
    }
}

// MARK: - Page messages

extension WebStillRenderer: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body as? [String: Any]
        MainActor.assumeIsolated { handle(body) }
    }

    private func handle(_ body: [String: Any]?) {
        guard let body else {
            finish(.failure(Failure.pageError(stage: "unknown", message: "malformed message")))
            return
        }

        guard body["ok"] as? Bool == true else {
            finish(.failure(Failure.pageError(
                stage: body["stage"] as? String ?? "unknown",
                message: body["error"] as? String ?? "unspecified"
            )))
            return
        }

        guard
            let dataURI = body["png"] as? String,
            let image = Self.decodePNGDataURI(dataURI)
        else {
            finish(.failure(Failure.undecodableImage))
            return
        }

        finish(.success(Result(
            image: image,
            triangles: body["triangles"] as? Int ?? 0,
            drawCalls: body["drawCalls"] as? Int ?? 0,
            pageMilliseconds: body["ms"] as? Int ?? 0
        )))
    }

    private static func decodePNGDataURI(_ uri: String) -> CGImage? {
        guard
            let comma = uri.firstIndex(of: ","),
            let data = Data(base64Encoded: String(uri[uri.index(after: comma)...])),
            let rep = NSBitmapImageRep(data: data)
        else { return nil }
        return rep.cgImage
    }
}

// MARK: - Navigation failures

extension WebStillRenderer: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        MainActor.assumeIsolated {
            finish(.failure(Failure.navigationFailed(error.localizedDescription)))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        MainActor.assumeIsolated {
            finish(.failure(Failure.navigationFailed(error.localizedDescription)))
        }
    }

    /// The signal that matters most for this spike: a seatbelt denial shows up here, not as
    /// a navigation error.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            finish(.failure(Failure.webContentTerminated))
        }
    }
}

// MARK: - Local resource serving

/// Serves the renderer bundle and the model over a private scheme.
///
/// Not a shortcut around `file://` CORS — it is the shape the real thing wants. Bytes flow
/// through Swift, so security-scoped access and sidecar resolution stay on the Swift side
/// where they already work, and the page never gets a filesystem path.
private final class LocalResourceHandler: NSObject, WKURLSchemeHandler {
    private let rendererRoot: URL
    private let model: URL

    init(rendererRoot: URL, model: URL) {
        self.rendererRoot = rendererRoot
        self.model = model
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }

        let payload: Data?
        let mimeType: String

        if url.path == "/model" {
            mimeType = "model/gltf-binary"
            payload = Self.readModel(at: model)
        } else if let file = resolveRendererFile(for: url.path) {
            mimeType = Self.mimeType(for: file.pathExtension)
            payload = try? Data(contentsOf: file)
        } else {
            mimeType = "application/octet-stream"
            payload = nil
        }

        guard let payload else {
            AppLog.error(AppLog.webThumb, "web still 404 \(url.path)")
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": String(payload.count),
                "Access-Control-Allow-Origin": "*",
            ]
        )!
        task.didReceive(response)
        task.didReceive(payload)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Confines requests to the bundled renderer folder — a page that went rogue must not be
    /// able to read arbitrary files through this handler.
    private func resolveRendererFile(for path: String) -> URL? {
        let prefix = "/renderer/"
        guard path.hasPrefix(prefix) else { return nil }
        let relative = String(path.dropFirst(prefix.count))
        guard !relative.isEmpty, !relative.contains("..") else { return nil }

        let candidate = rendererRoot.appendingPathComponent(relative).standardizedFileURL
        guard candidate.path.hasPrefix(rendererRoot.standardizedFileURL.path) else { return nil }
        return candidate
    }

    private static func readModel(at url: URL) -> Data? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    /// A wrong MIME type on the ES modules makes the import map fail silently with a blank
    /// page, so this matters more than it looks.
    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": "text/html"
        case "js", "mjs": "text/javascript"
        case "json": "application/json"
        case "wasm": "application/wasm"
        default: "application/octet-stream"
        }
    }
}
