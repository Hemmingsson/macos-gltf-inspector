import Foundation
import WebKit

/// Serves the bundled renderer and the file under inspection over a private scheme.
///
/// Not a workaround for `file://` CORS — it is the shape the app wants. Bytes flow through
/// Swift, so security-scoped access and sidecar resolution stay where they already work, and
/// the page never receives a filesystem path.
final class WebRendererResourceHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "gltf-inspector"

    /// Renderer files live at the scheme root rather than under a prefix: the Khronos renderer
    /// resolves its own `libs/` and `assets/` relative to the page, and rejects absolute URLs.
    private let rendererRoot: URL
    /// IBL `.hdr` files, served under `/environments/`. Kept as a separate root so the
    /// several-megabyte environments are not duplicated into the renderer folder.
    private let environmentRoot: URL?
    private var model: URL?

    init(rendererRoot: URL, environmentRoot: URL?) {
        self.rendererRoot = rendererRoot.standardizedFileURL
        self.environmentRoot = environmentRoot?.standardizedFileURL
    }

    /// The file currently under inspection. Swapping it is how a new model is loaded; the page
    /// always fetches the same `/model` URL.
    func setModel(_ url: URL?) {
        model = url
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }

        let payload: Data?
        let mimeType: String

        if url.path == "/model" {
            mimeType = "model/gltf-binary"
            payload = model.flatMap(Self.readSecurityScoped)
        } else if let file = resolveEnvironment(url.path) {
            mimeType = "image/vnd.radiance"
            payload = try? Data(contentsOf: file)
        } else if let file = resolve(url.path) {
            mimeType = Self.mimeType(for: file.pathExtension)
            payload = try? Data(contentsOf: file)
        } else {
            mimeType = "application/octet-stream"
            payload = nil
        }

        guard let payload else {
            AppLog.error(AppLog.webRenderer, "resource 404 \(url.path)")
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

    /// Confines every request to the bundled renderer folder. A page that went wrong must not
    /// be able to read arbitrary files through this handler.
    private func resolve(_ path: String) -> URL? {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !relative.isEmpty, !relative.contains("..") else { return nil }

        let candidate = rendererRoot.appendingPathComponent(relative).standardizedFileURL
        guard candidate.path.hasPrefix(rendererRoot.path + "/") else { return nil }
        return candidate
    }

    private func resolveEnvironment(_ path: String) -> URL? {
        let prefix = "/environments/"
        guard let environmentRoot, path.hasPrefix(prefix) else { return nil }
        let name = String(path.dropFirst(prefix.count))
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        return environmentRoot.appendingPathComponent(name)
    }

    private static func readSecurityScoped(_ url: URL) -> Data? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    /// A wrong MIME type on the ES modules makes the import fail silently with a blank page,
    /// so this matters more than it looks.
    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": "text/html"
        case "js", "mjs": "text/javascript"
        case "json": "application/json"
        case "wasm": "application/wasm"
        case "png": "image/png"
        case "hdr": "image/vnd.radiance"
        default: "application/octet-stream"
        }
    }
}
