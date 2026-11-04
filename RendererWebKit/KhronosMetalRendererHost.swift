import AppKit
import GLTFCore
import ImageIO
import Metal
import QuartzCore
import RendererMetal
import UniformTypeIdentifiers
import simd

/// Native hand port behind the same seam used by window, Quick Look, and thumbnails.
/// Selected only with GLTF_RENDERER=metal until the unchanged Khronos pixel gate passes.
///
/// Behaviour follows viewer.html, the oracle: the camera is a port of its `UserCamera` and
/// framing rules (`MetalUserCamera`), `apply` redoes only what the page redoes, and failures
/// surface the way `WebRendererHost` reports a dead page.
@MainActor
public final class KhronosMetalRendererHost: CanvasRendererHost {
    private let mode: WebRendererMode
    /// Still-mode edge in pixels; `renderStill(size:)` changes it, as the page resizes its canvas.
    private var stillSize: Int
    private var renderer: MetalRenderer?
    private let metalView = KhronosMetalView()
    private var look = WebPreviewCanvas.Look()
    private var modelURL: URL?
    private var camera = MetalUserCamera()
    /// Distance of the last fit — 100% on the zoom readout (`fitDistance` in viewer.html).
    private var fitDistance: Double?
    private var reportedZoom: Int?
    private var brokenBy: WebRendererError?
    /// True once the renderer failed to start or failed while drawing. Calls then fail fast with
    /// that error; the next `start()` makes a fresh renderer.
    public var isBroken: Bool { brokenBy != nil }
    public var onFailure: ((WebRendererError) -> Void)?
    public var onZoom: ((Int) -> Void)?
    public var view: NSView { metalView }
    public var rendererName: String { "Metal · Khronos 863b981" }
    public var logID: String { "mtl-" + String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 36) }

    public init(mode: WebRendererMode, size: Int = 512) {
        self.mode = mode
        stillSize = size
        metalView.host = self
    }

    public func start() async throws {
        if brokenBy != nil {
            // A fresh page: nothing survives from the one that died.
            renderer = nil
            brokenBy = nil
            look = WebPreviewCanvas.Look()
            modelURL = nil
            camera = MetalUserCamera()
            fitDistance = nil
            reportedZoom = nil
        }
        guard renderer == nil else { return }
        do {
            renderer = try MetalRenderer()
        } catch {
            let failure = WebRendererError.navigationFailed(error.localizedDescription)
            brokenBy = failure
            throw failure
        }
        metalView.metalLayer.device = renderer?.device
        AppLog.info(AppLog.webRenderer, "metal start host=\(logID) mode=\(mode.rawValue)")
    }

    private func readyRenderer() throws -> MetalRenderer {
        if let brokenBy { throw brokenBy }
        guard let renderer else { throw WebRendererError.notReady }
        return renderer
    }

    /// viewer.html `apply`: cheap values are assigned; only scene, variant, centring and
    /// projection changes do more, and only a scene or centring change refits.
    public func apply(_ next: WebPreviewCanvas.Look) async throws {
        if renderer == nil, brokenBy == nil { try await start() }
        _ = try readyRenderer()
        let previous = look
        look = next
        if previous.fieldOfView != next.fieldOfView { camera.yfov = next.fieldOfView * .pi / 180 }
        metalView.autoRotates = next.autoRotates
        let color = next.render.background
        metalView.metalLayer.backgroundColor = CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let sceneChanged = previous.sceneIndex != next.sceneIndex
        let variantChanged = previous.materialVariantIndex != next.materialVariantIndex
        let refit = previous.isCentered != next.isCentered || sceneChanged
        camera.isOrthographic = next.isOrthographic
        if let modelURL, sceneChanged || variantChanged {
            try await loadScene(modelURL)
        }
        if refit, renderer?.scene != nil {
            fitCamera()
        } else if previous.isOrthographic != next.isOrthographic {
            camera.applyProjection()
        }
        redraw()
    }

    @discardableResult public func load(model url: URL) async throws -> WebRendererHost.LoadInfo {
        let began = CFAbsoluteTimeGetCurrent()
        try await loadScene(url)
        let parseMs = Int((CFAbsoluteTimeGetCurrent() - began) * 1000)
        fitCamera()
        var firstFrameMs = 0
        if mode == .live {
            let drawn = CFAbsoluteTimeGetCurrent()
            if redraw() { firstFrameMs = Int((CFAbsoluteTimeGetCurrent() - drawn) * 1000) }
        }
        let scene = try readyRenderer().scene
        let statistics = scene.flatMap { scene in
            scene.gltfSceneIndex(for: look.sceneIndex).map { scene.pageStatistics(sceneIndex: $0) }
        } ?? (meshes: 0, faces: 0)
        let pixels = canvasPixels
        return WebRendererHost.LoadInfo(triangles: statistics.faces, meshes: statistics.meshes,
                                        width: pixels.width, height: pixels.height,
                                        parseMs: parseMs, firstFrameMs: firstFrameMs)
    }

    /// Loads (or reloads for a new scene or variant) without moving the camera.
    private func loadScene(_ url: URL) async throws {
        if self.renderer == nil, brokenBy == nil { try await start() }
        let renderer = try readyRenderer()
        do {
            try await renderer.load(url: url, sceneIndex: look.sceneIndex == 0 ? nil : look.sceneIndex,
                                    materialVariantIndex: look.materialVariantIndex)
        } catch {
            throw WebRendererError.callFailed("open: \(error.localizedDescription)")
        }
        modelURL = url
    }

    @discardableResult public func camera(_ command: CameraCommand) async throws -> RendererCameraState {
        _ = try readyRenderer()
        switch command.op {
        case "fit":
            fitCamera()
            // `fit` keeps the orbit angles while measuring; restate the front view.
            camera.orbitTo(azimuth: 0, elevation: 0, distance: camera.distance, target: camera.target)
            fitDistance = camera.distance
        case "orbit":
            camera.orbitTo(azimuth: command.azimuth ?? 0, elevation: command.elevation ?? 0,
                           distance: command.distance ?? camera.distance, target: camera.target)
        case "pose":
            if let pose = command.pose {
                camera.yfov = pose.yfov
                camera.znear = pose.znear
                camera.zfar = pose.zfar
                let target = pose.target.count == 3 ? SIMD3(pose.target[0], pose.target[1], pose.target[2]) : camera.target
                camera.orbitTo(azimuth: pose.azimuth, elevation: pose.elevation, distance: pose.distance, target: target)
                camera.baseDistance = pose.distance
            }
        case "get":
            break
        default:
            throw WebRendererError.callFailed("camera: unknown camera op '\(command.op)'")
        }
        if command.op != "get" {
            camera.applyProjection()
            redraw()
        }
        return state
    }

    /// viewer.html `still`: still mode renders at its own square size (`size` resizes it for good).
    /// Live mode renders the canvas as it is (Export PNG), or a `size` square when one is asked for.
    public func renderStill(size: Int? = nil) async throws -> CGImage {
        let renderer = try readyRenderer()
        if mode == .still, let size { stillSize = size }
        let pixels = mode == .live && size != nil ? (width: size!, height: size!) : canvasPixels
        guard renderer.scene != nil else { return try Self.blankImage(width: pixels.width, height: pixels.height) }
        do {
            return try renderer.image(look: look.render, pose: renderPose(width: pixels.width, height: pixels.height),
                                      width: pixels.width, height: pixels.height,
                                      orthographic: look.isOrthographic, debugOutput: debugOutput,
                                      wireframe: look.viewMode == .wireframe, overlays: overlays,
                                      fileCameraNodeIndex: look.fileCameraNodeIndex)
        } catch {
            throw WebRendererError.callFailed("still: \(error.localizedDescription)")
        }
    }

    public func renderStillPNG(size: Int? = nil) async throws -> Data {
        let image = try await renderStill(size: size)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw WebRendererError.undecodableResult("Metal PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WebRendererError.undecodableResult("Metal PNG") }
        return data as Data
    }

    // MARK: - Frame inputs

    /// The canvas the page would draw into: the still square, or the live drawable.
    private var canvasPixels: (width: Int, height: Int) {
        guard mode == .live else { return (stillSize, stillSize) }
        let size = metalView.metalLayer.drawableSize
        return (max(Int(size.width), 1), max(Int(size.height), 1))
    }

    private var canvasAspect: Double {
        let pixels = canvasPixels
        return Double(pixels.width) / Double(pixels.height)
    }

    /// `drawScene` records the canvas aspect on the user camera each frame it draws with it.
    private func renderPose(width: Int, height: Int) -> MetalCameraPose {
        if look.fileCameraNodeIndex == nil { camera.aspectRatio = Double(width) / Double(height) }
        return camera.pose
    }

    private var overlays: MetalOverlayOptions {
        MetalOverlayOptions(floor: look.showsFloor, origin: !look.isCentered, selectedNode: look.selectedNodeIndex,
                            extents: (SIMD3<Float>(camera.sceneMin), SIMD3<Float>(camera.sceneMax)))
    }

    private var debugOutput: Int {
        switch PageLook.debugOutput(look.viewMode) {
        case "Base Color": 1
        case "Normal Texture": 2
        case "Metallic": 3
        case "Roughness": 4
        case "Geometry Tangent": 5
        case "Texture Coordinates 0": 6
        case "Occlusion": 7
        case "Emissive": 8
        case "Alpha": 9
        case "Specular Strength": 10
        case "ClearCoat Strength": 11
        case "ClearCoat Roughness": 12
        case "ClearCoat Normal": 13
        default: 0
        }
    }

    // MARK: - Camera

    /// viewer.html `fitCamera` at the current canvas aspect; records the 100% zoom distance.
    private func fitCamera() {
        guard let scene = renderer?.scene, let index = scene.gltfSceneIndex(for: look.sceneIndex) else { return }
        camera.isOrthographic = look.isOrthographic
        if let fitted = camera.fit(extents: scene.pageExtents(sceneIndex: index), centered: look.isCentered,
                                   aspect: canvasAspect) {
            fitDistance = fitted
        }
    }

    private var state: RendererCameraState {
        func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }
        let target = camera.target
        return RendererCameraState(
            pose: CameraPose(azimuth: camera.rotAroundY * 180 / .pi, elevation: camera.rotAroundX * 180 / .pi,
                             distance: camera.distance, target: [target.x, target.y, target.z],
                             yfov: camera.yfov, znear: camera.znear, zfar: finite(camera.zfar)),
            sceneMin: [camera.sceneMin.x, camera.sceneMin.y, camera.sceneMin.z].map(finite),
            sceneMax: [camera.sceneMax.x, camera.sceneMax.y, camera.sceneMax.z].map(finite))
    }

    /// viewer.html `reportZoom`: live only, when the whole percent changes.
    private func reportZoom() {
        guard mode == .live, renderer?.scene != nil, let fitDistance, fitDistance > 0, camera.distance > 0 else { return }
        let percent = (fitDistance / camera.distance * 100).rounded()
        guard percent.isFinite, Int(percent) != reportedZoom else { return }
        reportedZoom = Int(percent)
        onZoom?(Int(percent))
    }

    // MARK: - Live surface

    /// Draws one live frame. On demand: the page redraws every animation frame, but nothing it
    /// draws changes between the inputs that call this.
    @discardableResult
    func redraw() -> Bool {
        reportZoom()
        guard mode == .live, metalView.window != nil, let renderer, renderer.scene != nil, brokenBy == nil,
              let drawable = metalView.metalLayer.nextDrawable() else { return false }
        do {
            let width = drawable.texture.width, height = drawable.texture.height
            let texture = try renderer.renderTexture(look: look.render, pose: renderPose(width: width, height: height),
                width: width, height: height,
                orthographic: look.isOrthographic, debugOutput: debugOutput, wireframe: look.viewMode == .wireframe,
                overlays: overlays, fileCameraNodeIndex: look.fileCameraNodeIndex)
            try renderer.present(texture, on: drawable)
            return true
        } catch {
            let failure = WebRendererError.pageError(error.localizedDescription)
            brokenBy = failure
            AppLog.error(AppLog.webRenderer, "metal renderer failed host=\(logID): \(failure)")
            onFailure?(failure)
            return false
        }
    }

    /// Pointer drag in view points, y down: `UserCamera.orbit(dx, dy)` or `pan(-dx, dy)`.
    func drag(dx: Double, dy: Double, pan: Bool) {
        guard renderer?.scene != nil else { return }
        if pan { camera.pan(-dx, dy) } else { camera.orbit(dx, dy) }
        redraw()
    }

    /// Wheel `deltaY` in CSS pixels: `UserCamera.zoomBy(deltaY * 0.01)`.
    func wheel(deltaY: Double) {
        guard renderer?.scene != nil else { return }
        camera.zoomBy(deltaY * 0.01)
        redraw()
    }

    /// One animation frame of auto-rotate: `orbit(1.2, 0)`.
    func rotate() {
        guard renderer?.scene != nil else { return }
        camera.orbit(1.2, 0)
        redraw()
    }

    private static func blankImage(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage()
        else { throw WebRendererError.undecodableResult("still") }
        return image
    }
}

@MainActor
private final class KhronosMetalView: NSView {
    weak var host: KhronosMetalRendererHost?
    var autoRotates = false { didSet { if autoRotates != oldValue { updateLink() } } }
    private var link: CADisplayLink?
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        wantsLayer = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func makeBackingLayer() -> CALayer {
        let l = CAMetalLayer()
        l.pixelFormat = .bgra8Unorm
        l.isOpaque = false
        return l
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() {
        super.layout()
        updateDrawableSize()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }
    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        host?.redraw()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateLink(); updateDrawableSize() }
    private func updateLink() {
        link?.invalidate(); link = nil
        guard autoRotates, window != nil else { return }
        let l = displayLink(target: self, selector: #selector(step))
        // The page turns once per animation frame, and WebKit paces those at 60 Hz.
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }
    @objc private func step() { host?.rotate() }

    // MARK: Input — the page's pointer and wheel handlers

    /// Window-space pointer position at the last drag step; nil when no drag started in this
    /// view. `event.deltaX/Y` is screen motion, which also moves with a dragged window.
    private var anchor: NSPoint?
    private var panning = false
    override func mouseDown(with event: NSEvent) { begin(event, pan: event.modifierFlags.contains(.shift)) }
    override func otherMouseDown(with event: NSEvent) { begin(event, pan: event.buttonNumber == 2) }
    override func mouseDragged(with event: NSEvent) { drag(event) }
    override func otherMouseDragged(with event: NSEvent) { drag(event) }
    override func mouseUp(with event: NSEvent) { anchor = nil }
    override func otherMouseUp(with event: NSEvent) { anchor = nil }
    private func begin(_ event: NSEvent, pan: Bool) {
        anchor = event.locationInWindow
        panning = pan
    }
    private func drag(_ event: NSEvent) {
        guard let start = anchor else { return }
        let location = event.locationInWindow
        anchor = location
        // Window space is y-up; the page's clientY deltas are y-down.
        host?.drag(dx: Double(location.x - start.x), dy: Double(start.y - location.y), pan: panning)
    }
    override func scrollWheel(with event: NSEvent) {
        // WebKit's wheel deltaY: the negated scroll delta, in pixels (40 per line step).
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 40
        host?.wheel(deltaY: -Double(delta))
    }
    override func magnify(with event: NSEvent) {
        // Not a page gesture; kept from the Filament host as an equivalent wheel dolly.
        host?.wheel(deltaY: -Double(event.magnification) * 500)
    }
}
