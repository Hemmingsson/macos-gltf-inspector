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
@MainActor
public final class WebRendererHost: NSObject {
    /// Model, environment and stats reported by the page after a load.
    public struct LoadInfo: Equatable {
        public var triangles: Int
        var meshes: Int
        var sceneCount: Int
        var animationCount: Int
        /// Drawing-buffer size the page ended up with. Zero-ish values mean the view was never
        /// laid out, which renders blank rather than failing.
        var width: Int
        var height: Int
        /// Page-side `loadGltf` wall time in ms, when the page reports it.
        var parseMs: Int
        /// Page-side `fitCamera` wall time in ms, when the page reports it.
        var fitMs: Int
        /// Live `load` only: first GPU `renderFrame` after parse. Zero in still mode.
        var firstFrameMs: Int
    }

    private static let messageName = "viewer"

    let mode: WebRendererMode

    private let resources: WebRendererResourceHandler
    /// Budget for each call on its own — never shared, so a slow call cannot time out another.
    var timeout: Duration
    private var webView: WKWebView!
    /// Navigation + page-message delegate. Private so the host's public API stays the renderer's,
    /// and weak back to the host, so the web view's configuration does not retain it.
    private var delegate: Delegate!

    private var nextCommandID = 1
    private var pending: [Int: CheckedContinuation<WebRendererEvent, Error>] = [:]
    private var timers: [Int: Task<Void, Never>] = [:]
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var isReady = false
    private var startTask: Task<Void, Error>?

    /// True once the page failed to start, crashed, lost its WebGL context or failed outside a
    /// call. Calls then fail fast with that error; the next `start()` loads a fresh page (a new
    /// WebContent process) instead of rethrowing it.
    public var isBroken: Bool { brokenBy != nil }
    private var brokenBy: Error?

    /// Called when a page that was running dies (WebContent crash, WebGL context loss, error
    /// outside a call). The owner decides whether to `start()` again and reload.
    var onFailure: ((WebRendererError) -> Void)?

    /// The renderer surface, for `.live` hosting. Untouched in `.still`.
    var view: NSView { webView }

    /// Short per-instance tag so the log shows whether a page start came from a new web view.
    var logID: String { String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 36) }

    /// Process uptime in ms — the debug log's wall stamps are whole seconds.
    static func uptimeMs() -> Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }

    public init(mode: WebRendererMode, timeout: Duration = .seconds(15)) throws {
        let bundle = Bundle(for: WebRendererHost.self)
        guard let rendererRoot = bundle.url(forResource: "web-renderer", withExtension: nil) else {
            throw WebRendererError.missingRendererBundle
        }
        let environmentRoot = KhronosEnvironments.bundledDirectory

        self.mode = mode
        self.timeout = timeout
        self.resources = WebRendererResourceHandler(
            rendererRoot: rendererRoot,
            environmentRoot: environmentRoot
        )
        super.init()

        let configuration = WKWebViewConfiguration()
        // An extension has no business persisting caches into its container.
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(resources, forURLScheme: WebRendererResourceHandler.scheme)
        delegate = Delegate(host: self)
        configuration.userContentController.add(delegate, name: Self.messageName)

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 512, height: 512), configuration: configuration)
        webView.navigationDelegate = delegate
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.isOpaque = false
        webView.layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// Loads the page and resolves once it reports `ready`. Safe to call repeatedly: a running
    /// or started page is joined; a page that failed or died is loaded again.
    public func start(size: Int? = nil) async throws {
        if let startTask {
            try await startTask.value
            if let size {
                _ = try await send { .configure(id: $0, mode: self.mode, size: size) }
            }
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            let began = clock.now
            AppLog.info(
                AppLog.webRenderer,
                "page start begin host=\(self.logID) mode=\(self.mode.rawValue) retry=\(self.brokenBy != nil) uptimeMs=\(Self.uptimeMs())"
            )
            self.brokenBy = nil
            self.isReady = false
            do {
                try await self.loadPage()
                _ = try await self.send { .configure(id: $0, mode: self.mode, size: size) }
            } catch {
                AppLog.error(AppLog.webRenderer, "page start failed host=\(self.logID): \(error)")
                self.brokenBy = error
                self.startTask = nil
                throw error
            }
            let elapsed = (clock.now - began).components
            let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
            AppLog.info(
                AppLog.webRenderer,
                "page start ready host=\(self.logID) mode=\(self.mode.rawValue) pageMs=\(ms) uptimeMs=\(Self.uptimeMs())"
            )
        }
        startTask = task
        try await task.value
    }

    private func loadPage() async throws {
        let url = URL(string: "\(WebRendererResourceHandler.scheme):///viewer.html")!
        let timer = Task { [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, let ready = self.readyContinuation else { return }
            self.readyContinuation = nil
            ready.resume(throwing: WebRendererError.timedOut)
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    /// Sends one command and waits for its matching reply.
    ///
    /// The caller receives the command id so a payload can be built with it — every command
    /// type is constructed through a static factory that takes the id.
    @discardableResult
    func send(_ make: (Int) -> WebRendererCommand) async throws -> WebRendererEvent {
        if let brokenBy { throw brokenBy }
        guard isReady else { throw WebRendererError.notReady }

        let id = nextCommandID
        nextCommandID += 1
        let command = make(id)
        let script = try command.javaScript()

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timers[id] = Task { [weak self, timeout] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.fail(id: id, with: WebRendererError.timedOut)
            }
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let error else { return }
                MainActor.assumeIsolated { self?.fail(id: id, with: error) }
            }
        }
    }

    /// Points the renderer at a file and loads it. The page always fetches `/model`; which
    /// bytes that resolves to is decided here, in Swift.
    ///
    /// Does not wait for HDR IBL: the page draws key+fill and starts the look's environment
    /// after the model; `renderStill` waits for it.
    @discardableResult
    public func load(model url: URL) async throws -> LoadInfo {
        resources.setModel(url)
        let name = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.lastPathComponent
        let event = try await send {
            .load(id: $0, url: "\(WebRendererResourceHandler.scheme):///model/\(name)")
        }
        return LoadInfo(
            triangles: event.triangles ?? 0,
            meshes: event.meshes ?? 0,
            sceneCount: event.sceneCount ?? 0,
            animationCount: event.animationCount ?? 0,
            width: event.width ?? 0,
            height: event.height ?? 0,
            parseMs: event.parseMs ?? 0,
            fitMs: event.fitMs ?? 0,
            firstFrameMs: event.firstFrameMs ?? 0
        )
    }

    /// The whole look, applied in one call. Before the first model it only records the
    /// environment; after, a changed environment is prefiltered before this returns.
    public func apply(_ look: WebPreviewCanvas.Look) async throws {
        try await apply(PageLook(look))
    }

    func apply(_ look: PageLook) async throws {
        try await send { .apply(id: $0, look: look) }
    }

    /// Evaluates an expression in the page and returns it as a string.
    ///
    /// Diagnostics and tests only — real work goes through a typed command so the contract
    /// stays visible on both sides.
    @discardableResult
    func evaluate(_ expression: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("String(\(expression))") { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String ?? "")
                }
            }
        }
    }

    /// Replays a complete camera pose. Nothing is inherited from the renderer's fit heuristic,
    /// which is what lets a recorded pose stay valid across renderer upgrades.
    func setCameraPose(_ pose: CameraPose) async throws {
        try await send { .setCameraPose(id: $0, pose: pose) }
    }

    /// Reads the current camera back, with the scene bounds the last fit measured — used to
    /// record a pose.
    func cameraState() async throws -> RendererCameraState {
        let event = try await send { .getCamera(id: $0) }
        guard let camera = event.camera else { throw WebRendererError.undecodableCameraPose }
        guard camera.isMeasurable else { throw WebRendererError.unmeasurableScene }
        return camera
    }

    /// Renders one frame and decodes it. `.still` mode in practice, though a live host can grab
    /// a frame too. The page waits for a pending IBL first, so a thumbnail is a lit model.
    public func renderStill() async throws -> CGImage {
        let event = try await send { .renderStill(id: $0) }
        guard
            let uri = event.png,
            let image = Self.decodePNGDataURI(uri)
        else { throw WebRendererError.undecodableImage }
        return image
    }

    // MARK: - Completion

    /// Resolves one waiter. Several paths race to report failure — timeout, WebContent death
    /// and the page's own error handler can all fire for a single cause — so everything funnels
    /// through here and later calls are dropped.
    private func finish(id: Int, with result: Result<WebRendererEvent, Error>) {
        timers.removeValue(forKey: id)?.cancel()
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
    }

    private func fail(id: Int, with error: Error) {
        finish(id: id, with: .failure(error))
    }

    /// The page is gone or unusable: fails every outstanding waiter, including the page load,
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
        let waiters = pending
        pending.removeAll()
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        for (_, continuation) in waiters {
            continuation.resume(throwing: error)
        }
        AppLog.error(AppLog.webRenderer, "web renderer failed host=\(logID): \(error)")
        if wasRunning { onFailure?(error) }
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

// MARK: - Page messages

extension WebRendererHost {
    fileprivate func handle(_ body: Any) {
        guard let event = WebRendererEvent(body: body) else {
            failAll(WebRendererError.malformedMessage)
            return
        }

        switch event.name {
        case .ready:
            isReady = true
            if let readyContinuation {
                self.readyContinuation = nil
                readyContinuation.resume()
            }

        case .result:
            guard let id = event.id else {
                failAll(WebRendererError.malformedMessage)
                return
            }
            finish(id: id, with: .success(event))

        case .failed:
            guard let id = event.id else {
                failAll(WebRendererError.malformedMessage)
                return
            }
            fail(id: id, with: WebRendererError.commandFailed(event.message ?? "unspecified"))

        case .progress:
            // Status chrome is driven from Swift (JSON peek). Ignore so a late page
            // ping cannot fail an in-flight `load`.
            return

        case .warning:
            // Khronos reports many load problems through `console.error` rather than throwing.
            AppLog.info(AppLog.webRenderer, "page warning host=\(logID): \(event.message ?? "")")

        case .contextLost:
            failAll(WebRendererError.contextLost)

        case .error:
            // Outside any command handler, so there is no id to blame — fail everyone waiting.
            failAll(WebRendererError.pageError(
                stage: event.stage ?? "unknown",
                message: event.message ?? "unspecified"
            ))
        }
    }
}

/// Page messages and navigation failures, kept off the host's public surface. Holds the host
/// weakly: `WKUserContentController` retains its handlers.
private final class Delegate: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var host: WebRendererHost?

    init(host: WebRendererHost) {
        self.host = host
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { host?.handle(body) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { host?.failAll(WebRendererError.navigationFailed(message)) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { host?.failAll(WebRendererError.navigationFailed(message)) }
    }

    /// A crash, jetsam, or a seatbelt denial (which surfaces here, not as a navigation error —
    /// `com.apple.security.network.client` on a sandboxed target is what prevents that one).
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated { host?.failAll(WebRendererError.webContentTerminated) }
    }
}
