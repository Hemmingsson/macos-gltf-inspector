import AppKit
import CoreGraphics
import Foundation
import GLTFCore
import WebKit

/// Owns the `WKWebView` that every surface renders through — Finder thumbnail, Quick Look
/// preview and the document window.
///
/// Two modes, one page. In `.still` the web view is never added to a window, which is the
/// property that makes non-UI `QLThumbnailProvider` rendering possible; pixels come back from
/// `canvas.toDataURL()` rather than `takeSnapshot`, so nothing depends on the view being
/// layer-backed or on screen. In `.live` the same page renders continuously into `view`.
///
/// Swift → page is `callAsyncJavaScript` on five page functions (`call`), each with its own
/// timeout. Page → Swift is a handful of push events (`ready`, `warning`, `contextlost`,
/// `error`) with no replies.
@MainActor
public final class WebRendererHost {
    /// Model and stats reported by the page after a load.
    public struct LoadInfo: Equatable, Decodable {
        public var triangles: Int
        var meshes: Int
        var sceneCount: Int
        var animationCount: Int
        /// Drawing-buffer size the page ended up with. Zero-ish values mean the view was never
        /// laid out, which renders blank rather than failing.
        var width: Int
        var height: Int
        /// Page-side `loadGltf` wall time in ms.
        var parseMs: Int
        /// Page-side `fitCamera` wall time in ms.
        var fitMs: Int
        /// Live only: first GPU `renderFrame` after parse. Zero in still mode.
        var firstFrameMs: Int
    }

    /// `stats()`: what the page is drawing right now. Diagnostics and tests.
    struct Stats: Decodable, Equatable {
        var width: Int
        var height: Int
        var triangles: Int
        var meshes: Int
        /// Computed page background, e.g. `rgba(0, 0, 0, 0)`.
        var background: String
    }

    fileprivate static let messageName = "viewer"
    /// Calls `window.__viewer[fn]` with one JSON argument and hands back its result as JSON text
    /// — a `String` is the one result type that crosses the bridge without guessing.
    private static let callScript = "return JSON.stringify((await window.__viewer[fn](JSON.parse(arg))) ?? {});"

    let mode: WebRendererMode
    /// Still-mode drawing-buffer edge in pixels, until a `renderStill(size:)` changes it.
    let size: Int
    /// Budget for each call on its own — never shared, so a slow call cannot time out another.
    var timeout: Duration

    private let resources: WebRendererResourceHandler
    private let webView: WKWebView
    /// Navigation + page-message delegate, kept off the public API and holding the host weakly
    /// (`WKUserContentController` retains its handlers).
    private let delegate: Delegate

    private var nextCallID = 0
    private var calls: [Int: CheckedContinuation<String, Error>] = [:]
    private var timers: [Int: Task<Void, Never>] = [:]
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var isReady = false
    private var startTask: Task<Void, Error>?

    /// True once the page failed to start, crashed, lost its WebGL context or failed outside a
    /// call. Calls then fail fast with that error; the next `start()` loads a fresh page (a new
    /// WebContent process) instead of rethrowing it.
    public var isBroken: Bool { brokenBy != nil }
    private var brokenBy: WebRendererError?

    /// Called when a page that was running dies. The owner decides whether to `start()` again.
    var onFailure: ((WebRendererError) -> Void)?

    /// The renderer surface, for `.live` hosting. Untouched in `.still`.
    var view: NSView { webView }

    /// Short per-instance tag so the log shows whether a page start came from a new web view.
    var logID: String { String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 36) }

    /// Process uptime in ms — the debug log's wall stamps are whole seconds.
    static func uptimeMs() -> Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }

    public init(mode: WebRendererMode, size: Int = 512, timeout: Duration = .seconds(15)) throws {
        guard let rendererRoot = Bundle(for: WebRendererHost.self).url(forResource: "web-renderer", withExtension: nil)
        else { throw WebRendererError.missingRendererBundle }

        self.mode = mode
        self.size = size
        self.timeout = timeout
        resources = WebRendererResourceHandler(
            rendererRoot: rendererRoot,
            environmentRoot: KhronosEnvironments.bundledDirectory
        )
        delegate = Delegate()

        let configuration = WKWebViewConfiguration()
        // An extension has no business persisting caches into its container.
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(resources, forURLScheme: WebRendererResourceHandler.scheme)
        configuration.userContentController.add(delegate, name: Self.messageName)

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 512, height: 512), configuration: configuration)
        webView.navigationDelegate = delegate
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.isOpaque = false
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        delegate.host = self
    }

    // MARK: - Page API

    /// Loads the page and resolves once it reports `ready`. Safe to call repeatedly: a running
    /// or starting page is joined; a page that failed or died is loaded again.
    public func start() async throws {
        if let startTask {
            return try await startTask.value
        }
        let task = Task {
            let began = ContinuousClock.now
            AppLog.info(
                AppLog.webRenderer,
                "page start begin host=\(logID) mode=\(mode.rawValue) retry=\(brokenBy != nil) uptimeMs=\(Self.uptimeMs())"
            )
            brokenBy = nil
            do {
                try await loadPage()
            } catch {
                AppLog.error(AppLog.webRenderer, "page start failed host=\(logID): \(error)")
                brokenBy = error as? WebRendererError ?? .navigationFailed("\(error)")
                startTask = nil
                throw error
            }
            AppLog.info(
                AppLog.webRenderer,
                "page start ready host=\(logID) mode=\(mode.rawValue) pageMs=\(Self.ms(since: began)) uptimeMs=\(Self.uptimeMs())"
            )
        }
        startTask = task
        try await task.value
    }

    /// Points the renderer at a file and loads it. The page always fetches `/model/<name>`;
    /// which bytes (and sidecars) that resolves to is decided here, in Swift.
    ///
    /// Does not wait for HDR IBL: the page draws key+fill and starts the look's environment
    /// after the model; `renderStill` waits for it.
    @discardableResult
    public func load(model url: URL) async throws -> LoadInfo {
        resources.setModel(url)
        let name = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.lastPathComponent
        return try await call("open", ["url": "\(WebRendererResourceHandler.scheme):///model/\(name)"])
    }

    /// The whole look, applied in one call. Before the first model it only records the
    /// environment; after, a changed environment is prefiltered before this returns.
    public func apply(_ look: WebPreviewCanvas.Look) async throws {
        try await apply(PageLook(look))
    }

    func apply(_ look: PageLook) async throws {
        let _: Empty = try await call("apply", look)
    }

    /// Moves or reads the camera; always answers with the resulting state.
    @discardableResult
    func camera(_ command: CameraCommand) async throws -> RendererCameraState {
        try await call("camera", command)
    }

    /// The current camera with the scene bounds the last fit measured — used to frame presets
    /// and to record a pose. Fails for a scene with nothing to frame.
    func cameraState() async throws -> RendererCameraState {
        let state = try await camera(.get)
        guard state.isMeasurable, state.pose.isFinite else { throw WebRendererError.unmeasurableScene }
        return state
    }

    func stats() async throws -> Stats {
        try await call("stats", Empty())
    }

    /// Renders one frame and decodes it. `.still` mode in practice, though a live host can grab
    /// a frame too. The page waits for a pending IBL first, so a thumbnail is a lit model.
    public func renderStill(size: Int? = nil) async throws -> CGImage {
        struct Still: Decodable { var png: String }
        let still: Still = try await call("still", ["size": size])
        guard
            let comma = still.png.firstIndex(of: ","),
            let data = Data(base64Encoded: String(still.png[still.png.index(after: comma)...])),
            let image = NSBitmapImageRep(data: data)?.cgImage
        else { throw WebRendererError.undecodableResult("still") }
        return image
    }

    /// Evaluates an expression in the page. Tests and diagnostics only — work goes through `call`.
    @discardableResult
    func evaluate(_ expression: String) async throws -> String {
        let value = try await webView.callAsyncJavaScript(
            "return String(\(expression));", arguments: [:], in: nil, contentWorld: .page
        )
        return value as? String ?? ""
    }

    // MARK: - Bridge

    private struct Empty: Codable {}

    /// One page function, one JSON argument, one decoded result, one timeout of its own.
    func call<Result: Decodable>(_ function: String, _ argument: some Encodable) async throws -> Result {
        if let brokenBy { throw brokenBy }
        guard isReady else { throw WebRendererError.notReady }

        let json = String(decoding: try JSONEncoder().encode(argument), as: UTF8.self)
        nextCallID += 1
        let id = nextCallID
        let text: String = try await withCheckedThrowingContinuation { continuation in
            calls[id] = continuation
            timers[id] = Task { [weak self, timeout] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.finish(id, .failure(WebRendererError.timedOut))
            }
            webView.callAsyncJavaScript(
                Self.callScript, arguments: ["fn": function, "arg": json], in: nil, in: .page
            ) { [weak self] result in
                MainActor.assumeIsolated {
                    self?.finish(id, result.flatMap { value in
                        guard let text = value as? String else {
                            return .failure(WebRendererError.undecodableResult(function))
                        }
                        return .success(text)
                    }.mapError { Self.pageError($0, in: function) })
                }
            }
        }
        do {
            return try JSONDecoder().decode(Result.self, from: Data(text.utf8))
        } catch {
            throw WebRendererError.undecodableResult("\(function): \(error)")
        }
    }

    /// A JS throw arrives as `WKError.javaScriptExceptionOccurred` with the page's message in
    /// `userInfo`; keep that message (for the log), not WebKit's generic description.
    private static func pageError(_ error: Error, in function: String) -> Error {
        if error is WebRendererError { return error }
        let info = (error as NSError).userInfo
        let message = info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
        return WebRendererError.callFailed("\(function): \(message)")
    }

    private func finish(_ id: Int, _ result: Swift.Result<String, Error>) {
        timers.removeValue(forKey: id)?.cancel()
        calls.removeValue(forKey: id)?.resume(with: result)
    }

    private func loadPage() async throws {
        var components = URLComponents()
        components.scheme = WebRendererResourceHandler.scheme
        components.path = "/viewer.html"
        components.queryItems = [
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "size", value: String(size)),
        ]
        let timer = Task { [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, let ready = self.readyContinuation else { return }
            self.readyContinuation = nil
            ready.resume(throwing: WebRendererError.timedOut)
        }
        defer { timer.cancel() }
        isReady = false
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            webView.load(URLRequest(url: components.url!))
        }
    }

    /// The page is gone or unusable: fails every outstanding call, including the page start,
    /// and tells the owner when a page that had started dies.
    fileprivate func failAll(_ error: WebRendererError) {
        let wasRunning = isReady
        brokenBy = error
        isReady = false
        startTask = nil
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(throwing: error)
        }
        for id in Array(calls.keys) {
            finish(id, .failure(error))
        }
        AppLog.error(AppLog.webRenderer, "web renderer failed host=\(logID): \(error)")
        if wasRunning { onFailure?(error) }
    }

    fileprivate func handle(event name: String, message: String?) {
        switch name {
        case "ready":
            isReady = true
            readyContinuation?.resume()
            readyContinuation = nil
        case "warning":
            // Khronos reports many load problems through `console.error` rather than throwing.
            AppLog.info(AppLog.webRenderer, "page warning host=\(logID): \(message ?? "")")
        case "contextlost":
            failAll(.contextLost)
        default:
            // An error outside any call: nothing to blame it on, so the page is done.
            failAll(.pageError(message ?? name))
        }
    }

    private static func ms(since start: ContinuousClock.Instant) -> Int {
        let elapsed = (ContinuousClock.now - start).components
        return Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
    }
}

/// Page messages and navigation failures, kept off the host's public surface.
private final class Delegate: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var host: WebRendererHost?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? [String: Any]
        let name = body?["event"] as? String ?? "error"
        let text = body?["message"] as? String
        MainActor.assumeIsolated { host?.handle(event: name, message: text) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { host?.failAll(.navigationFailed(message)) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { host?.failAll(.navigationFailed(message)) }
    }

    /// A crash, jetsam, or a seatbelt denial (which surfaces here, not as a navigation error —
    /// `com.apple.security.network.client` on a sandboxed target is what prevents that one).
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated { host?.failAll(.webContentTerminated) }
    }
}
