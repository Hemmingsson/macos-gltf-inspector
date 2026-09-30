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
    private let timeout: Duration
    private var webView: WKWebView!

    private var nextCommandID = 1
    private var pending: [Int: CheckedContinuation<WebRendererEvent, Error>] = [:]
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var isReady = false
    private var startTask: Task<Void, Error>?
    /// Desired HDR stem. Applied after the first `load` so first paint does not wait on IBL.
    private var pendingEnvironmentName: String?
    private var appliedEnvironmentName: String?
    private var hasLoadedModel = false
    private var environmentTask: Task<Void, Error>?

    /// The renderer surface, for `.live` hosting. Untouched in `.still`.
    var view: NSView { webView }

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
        configuration.userContentController.add(self, name: Self.messageName)

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 512, height: 512), configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.isOpaque = false
        webView.layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// Loads the page and resolves once it reports `ready`. Safe to call repeatedly; the work
    /// happens once.
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
            try await self.loadPage()
            _ = try await self.send { .configure(id: $0, mode: self.mode, size: size) }
        }
        startTask = task
        try await task.value
    }

    private func loadPage() async throws {
        let url = URL(string: "\(WebRendererResourceHandler.scheme):///viewer.html")!
        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            armTimeout()
            webView.load(URLRequest(url: url))
        }
    }

    /// Sends one command and waits for its matching reply.
    ///
    /// The caller receives the command id so a payload can be built with it — every command
    /// type is constructed through a static factory that takes the id.
    @discardableResult
    func send(_ make: (Int) -> WebRendererCommand) async throws -> WebRendererEvent {
        guard isReady else { throw WebRendererError.notReady }

        let id = nextCommandID
        nextCommandID += 1
        let command = make(id)
        let script = try command.javaScript()

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            armTimeout()
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let error else { return }
                MainActor.assumeIsolated { self?.fail(id: id, with: error) }
            }
        }
    }

    /// Points the renderer at a file and loads it. The page always fetches `/model`; which
    /// bytes that resolves to is decided here, in Swift.
    ///
    /// Does not wait for HDR IBL. A prior `setEnvironment` is optional; the page draws
    /// key+fill until the probe lands. IBL is kicked off after `loadGltf` returns.
    @discardableResult
    public func load(model url: URL) async throws -> LoadInfo {
        resources.setModel(url)
        let name = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.lastPathComponent
        let event = try await send {
            .load(id: $0, url: "\(WebRendererResourceHandler.scheme):///model/\(name)")
        }
        hasLoadedModel = true
        startEnvironmentIfNeeded()
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

    /// Records the bundled `.hdr` stem. Before the first model load this is a cheap
    /// bookkeeping call — the HDR fetch runs after `load` so first paint is not gated on IBL.
    /// After a model is on screen, a new name applies immediately (look changes).
    public func setEnvironment(named name: String) async throws {
        pendingEnvironmentName = name
        guard hasLoadedModel else { return }
        try await finishEnvironment()
        if appliedEnvironmentName == name { return }
        try await applyEnvironment(named: name)
    }

    /// Khronos `GltfState.ToneMaps` value, by name.
    public func setToneMapping(named name: String) async throws {
        try await send { .setToneMapping(id: $0, name: name) }
    }

    /// Evaluates an expression in the page and returns it as a string.
    ///
    /// Diagnostics and tests only — real work goes through a typed command so the contract
    /// stays visible on both sides.
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

    /// Renders one frame and decodes it. `.still` mode only in practice, though nothing stops
    /// a live host from grabbing a frame.
    ///
    /// Joins deferred IBL first so a thumbnail taken after `load` is still a lit model.
    public func renderStill() async throws -> CGImage {
        try await finishEnvironment()
        let event = try await send { .renderStill(id: $0) }
        guard
            let uri = event.png,
            let image = Self.decodePNGDataURI(uri)
        else { throw WebRendererError.undecodableImage }
        return image
    }

    // MARK: - Deferred IBL

    /// Kicks HDR apply after first `load` without blocking the load result.
    private func startEnvironmentIfNeeded() {
        guard let name = pendingEnvironmentName, name != appliedEnvironmentName else { return }
        guard environmentTask == nil else { return }
        environmentTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.applyEnvironment(named: name)
            } catch {
                AppLog.error(AppLog.webRenderer, "environment apply failed: \(error.localizedDescription)")
                self.environmentTask = nil
                throw error
            }
        }
    }

    private func finishEnvironment() async throws {
        if let environmentTask {
            defer { self.environmentTask = nil }
            try await environmentTask.value
        }
        if let name = pendingEnvironmentName, name != appliedEnvironmentName {
            try await applyEnvironment(named: name)
        }
    }

    private func applyEnvironment(named name: String) async throws {
        try await send {
            .setEnvironment(id: $0, url: "\(WebRendererResourceHandler.scheme):///environments/\(name).hdr")
        }
        appliedEnvironmentName = name
    }

    // MARK: - Completion

    /// Resolves one waiter. Several paths race to report failure — timeout, WebContent death
    /// and the page's own error handler can all fire for a single cause — so everything funnels
    /// through here and later calls are dropped.
    private func finish(id: Int, with result: Result<WebRendererEvent, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
    }

    private func fail(id: Int, with error: Error) {
        finish(id: id, with: .failure(error))
    }

    /// Fails every outstanding waiter, including the page load.
    private func failAll(_ error: Error) {
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(throwing: error)
        }
        let waiters = pending
        pending.removeAll()
        for (_, continuation) in waiters {
            continuation.resume(throwing: error)
        }
        AppLog.error(AppLog.webRenderer, "web renderer failed: \(error.localizedDescription)")
    }

    private func armTimeout() {
        Task { [timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            if !self.pending.isEmpty || self.readyContinuation != nil {
                self.failAll(WebRendererError.timedOut)
            }
        }
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

extension WebRendererHost: WKScriptMessageHandler {
    public nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body
        MainActor.assumeIsolated { handle(body) }
    }

    private func handle(_ body: Any) {
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

        case .error:
            // Outside any command handler, so there is no id to blame — fail everyone waiting.
            failAll(WebRendererError.pageError(
                stage: event.stage ?? "unknown",
                message: event.message ?? "unspecified"
            ))
        }
    }
}

// MARK: - Navigation failures

extension WebRendererHost: WKNavigationDelegate {
    public nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        MainActor.assumeIsolated {
            failAll(WebRendererError.navigationFailed(error.localizedDescription))
        }
    }

    public nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        MainActor.assumeIsolated {
            failAll(WebRendererError.navigationFailed(error.localizedDescription))
        }
    }

    /// A seatbelt denial surfaces here, not as a navigation error. Adding
    /// `com.apple.security.network.client` to a sandboxed target is what prevents it.
    public nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            failAll(WebRendererError.webContentTerminated)
        }
    }
}
