import Foundation
import GLTFCore
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
    private var model: URL?

    init(rendererRoot: URL) {
        self.rendererRoot = rendererRoot.standardizedFileURL
    }

    /// The file currently under inspection. Swapping it is how a new model is loaded; the page
    /// fetches it as `/model/<name>`.
    func setModel(_ url: URL?) {
        model = url
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }

        let payload: Data?
        let mimeType: String

        if url.path.hasPrefix("/model/") {
            mimeType = Self.modelMimeType(url.path)
            payload = resolveModel(url.path)
        } else if let file = Self.resolveEnvironment(url.path) {
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

    /// Serves the inspected file and its sidecars from the security-scoped folder.
    /// `/model/<basename>` is the primary file; `/model/<relative>` is a sibling.
    private func resolveModel(_ path: String) -> Data? {
        guard let model, path.hasPrefix("/model/") else { return nil }
        let remainder = String(path.dropFirst("/model/".count))

        let decoded = remainder.removingPercentEncoding ?? remainder
        guard !decoded.contains("..") else { return nil }

        let file: URL
        if decoded.isEmpty || decoded == model.lastPathComponent {
            file = model
        } else {
            file = model.deletingLastPathComponent().appendingPathComponent(decoded)
        }

        let folder = model.deletingLastPathComponent().standardizedFileURL.path
        guard file.standardizedFileURL.path.hasPrefix(folder + "/") || file.standardizedFileURL == model.standardizedFileURL
        else { return nil }

        return Self.readSecurityScoped(file)
    }

    private static func modelMimeType(_ path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "gltf", "json": return "model/gltf+json"
        case "bin": return "application/octet-stream"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "model/gltf-binary"
        }
    }

    /// Confines every request to the bundled renderer folder. A page that went wrong must not
    /// be able to read arbitrary files through this handler.
    private func resolve(_ path: String) -> URL? {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !relative.isEmpty, !relative.contains("..") else { return nil }

        let candidate = rendererRoot.appendingPathComponent(relative).standardizedFileURL
        guard candidate.path.hasPrefix(rendererRoot.path + "/") else { return nil }
        return candidate
    }

    /// `/environments/<stem>.hdr` is the bundled Khronos HDR of that name (it ships in
    /// GLTFCore, not in the renderer folder). Nothing else under the prefix is served.
    private static func resolveEnvironment(_ path: String) -> URL? {
        let prefix = "/environments/"
        guard path.hasPrefix(prefix), path.hasSuffix(".hdr") else { return nil }
        let stem = String(path.dropFirst(prefix.count).dropLast(".hdr".count))
        return KhronosEnvironments(rawValue: stem)?.bundledURL
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
        default: "application/octet-stream"
        }
    }
}
