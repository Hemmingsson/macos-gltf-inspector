import AppKit
import FilamentBridge
import GLTFCore
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

/// Google's Filament (Metal, gltfio) behind the same host surface as the WebKit page.
///
/// `.live` draws into `FilamentMetalView` from its display link and orbits on mouse and trackpad
/// input. `.still` never shows a view and reads one offscreen frame back. Main thread only: the
/// process-wide Filament engine is not thread-safe.
@MainActor
public final class FilamentRendererHost: CanvasRendererHost {
    let mode: WebRendererMode
    /// Still-mode edge in pixels, until a `renderStill(size:)` changes it.
    let size: Int

    private var renderer: FLRenderer?
    private let metalView = FilamentMetalView()
    private var appliedEnvironment: KhronosEnvironments?
    private var look = WebPreviewCanvas.Look()

    // Orbit camera, in the page's convention (`RenderCamera.lookDirection`).
    private var target = SIMD3<Double>(0, 0, 0)
    private var azimuth = 0.0
    private var elevation = 0.0
    private var distance = 1.0
    private var sceneMin: [Double] = []
    private var sceneMax: [Double] = []

    public var onFailure: ((WebRendererError) -> Void)?
    public var onZoom: ((Int) -> Void)?
    /// Distance of the last fit; zoom percent is measured against it.
    private var fittedDistance: Double?
    private var reportedZoom: Int?
    public var isBroken: Bool { false }
    public var view: NSView { metalView }
    public var rendererName: String { "Filament 1.80 · Metal" }
    public var logID: String { "fl-" + String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 36) }

    public init(mode: WebRendererMode, size: Int = 512) {
        self.mode = mode
        self.size = size
        metalView.host = self
    }

    public func start() async throws {
        if renderer != nil { return }
        let began = ContinuousClock.now
        let made: FLRenderer
        do {
            made = try FLRenderer.make()
        } catch {
            throw WebRendererError.navigationFailed(error.localizedDescription)
        }
        renderer = made
        if mode == .live { metalView.attach(made) }
        AppLog.info(
            AppLog.webRenderer,
            "filament start host=\(logID) mode=\(mode.rawValue) ms=\((ContinuousClock.now - began).milliseconds)"
        )
    }

    public func apply(_ look: WebPreviewCanvas.Look) async throws {
        try await start()
        guard let renderer else { throw WebRendererError.notReady }
        self.look = look
        let render = look.render
        if appliedEnvironment != render.environment {
            guard let url = render.environment.bundledURL else { throw WebRendererError.missingRendererBundle }
            do {
                try renderer.setEnvironmentPath(url.path)
            } catch {
                throw WebRendererError.callFailed("environment: \(error.localizedDescription)")
            }
            appliedEnvironment = render.environment
        }
        renderer.setEnvironmentIntensity(Float(render.environmentIntensity), yawDegrees: Float(render.environmentYawDegrees))
        renderer.setExposure(Float(pow(2, render.exposureEV)))
        renderer.setToneMapper(Self.toneMapper(render.toneMapping))
        let color = render.background
        renderer.setBackgroundRed(Float(color.red), green: Float(color.green), blue: Float(color.blue), alpha: Float(color.alpha))
        renderer.applyMaterialVariant(look.materialVariantIndex ?? -1)
        renderer.playsAnimation = mode == .live
        metalView.autoRotates = look.autoRotates
        updateCamera()
    }

    @discardableResult
    public func load(model url: URL) async throws -> WebRendererHost.LoadInfo {
        try await start()
        guard let renderer else { throw WebRendererError.notReady }
        let began = ContinuousClock.now
        do {
            try renderer.loadModel(atPath: url.path)
        } catch {
            throw WebRendererError.callFailed("open: \(error.localizedDescription)")
        }
        renderer.applyMaterialVariant(look.materialVariantIndex ?? -1)
        let low = renderer.boundsMin
        let high = renderer.boundsMax
        sceneMin = [Double(low.x), Double(low.y), Double(low.z)]
        sceneMax = [Double(high.x), Double(high.y), Double(high.z)]
        fit()
        let parse = (ContinuousClock.now - began).milliseconds
        let pixels = metalView.drawablePixels
        return WebRendererHost.LoadInfo(
            triangles: 0,
            meshes: renderer.renderableCount,
            width: mode == .live ? pixels.width : size,
            height: mode == .live ? pixels.height : size,
            parseMs: parse,
            firstFrameMs: 0
        )
    }

    @discardableResult
    public func camera(_ command: CameraCommand) async throws -> RendererCameraState {
        switch command.op {
        case "fit":
            fit()
        case "orbit":
            azimuth = command.azimuth ?? azimuth
            elevation = command.elevation ?? elevation
            distance = command.distance ?? distance
            updateCamera()
        case "pose":
            if let pose = command.pose {
                azimuth = pose.azimuth
                elevation = pose.elevation
                distance = pose.distance
                if pose.target.count == 3 { target = SIMD3(pose.target[0], pose.target[1], pose.target[2]) }
                updateCamera()
            }
        default:
            break
        }
        return cameraState
    }

    public func renderStillPNG(size: Int? = nil) async throws -> Data {
        let image = try await renderStill(size: size)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw WebRendererError.undecodableResult("still") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WebRendererError.undecodableResult("still") }
        return data as Data
    }

    public func renderStill(size: Int? = nil) async throws -> CGImage {
        guard let renderer else { throw WebRendererError.notReady }
        let width: Int
        let height: Int
        if let size {
            (width, height) = (size, size)
        } else if mode == .live {
            let pixels = metalView.drawablePixels
            (width, height) = (max(pixels.width, 1), max(pixels.height, 1))
        } else {
            (width, height) = (self.size, self.size)
        }
        do {
            return try renderer.copyStill(withWidth: width, height: height)
        } catch {
            throw WebRendererError.callFailed("still: \(error.localizedDescription)")
        }
    }

    // MARK: - Camera

    private var aspect: Float {
        guard mode == .live else { return 1 }
        let pixels = metalView.drawablePixels
        return pixels.height > 0 ? Float(pixels.width) / Float(pixels.height) : 1
    }

    private var boundingRadius: Double {
        guard sceneMin.count == 3, sceneMax.count == 3 else { return 1 }
        let diagonal = (0..<3).map { sceneMax[$0] - sceneMin[$0] }
        return max((diagonal.reduce(0) { $0 + $1 * $1 }).squareRoot() / 2, 1e-4)
    }

    private func fit() {
        azimuth = 0
        elevation = 0
        guard sceneMin.count == 3, sceneMax.count == 3 else { return updateCamera() }
        target = SIMD3((sceneMin[0] + sceneMax[0]) / 2, (sceneMin[1] + sceneMax[1]) / 2, (sceneMin[2] + sceneMax[2]) / 2)
        let extent = SIMD3<Float>(
            Float(sceneMax[0] - sceneMin[0]), Float(sceneMax[1] - sceneMin[1]), Float(sceneMax[2] - sceneMin[2])
        )
        distance = Double(
            RenderCamera.fitDistance(
                extent: extent,
                toCamera: RenderCamera.lookDirection(azimuthDegrees: 0, elevationDegrees: 0),
                aspect: aspect,
                fieldOfViewInDegrees: Float(look.fieldOfView)
            )
        )
        fittedDistance = distance
        updateCamera()
    }

    private var clipPlanes: (near: Double, far: Double) {
        let radius = boundingRadius
        return (max(distance - radius * 4, distance * 0.001, 1e-4), distance + radius * 8)
    }

    func updateCamera() {
        guard let renderer else { return }
        if let fittedDistance, distance > 0 {
            let percent = Int((fittedDistance / distance * 100).rounded())
            if percent != reportedZoom {
                reportedZoom = percent
                onZoom?(percent)
            }
        }
        let direction = RenderCamera.lookDirection(azimuthDegrees: azimuth, elevationDegrees: elevation)
        let eye = target + SIMD3<Double>(Double(direction.x), Double(direction.y), Double(direction.z)) * distance
        renderer.look(fromEye: eye, target: target)
        let planes = clipPlanes
        if look.isOrthographic {
            let height = 2 * distance * tan(look.fieldOfView * .pi / 360)
            renderer.setOrthographicHeight(height, near: planes.near, far: planes.far)
        } else {
            renderer.setPerspectiveFieldOfView(look.fieldOfView, near: planes.near, far: planes.far)
        }
    }

    private var cameraState: RendererCameraState {
        let planes = clipPlanes
        return RendererCameraState(
            pose: CameraPose(
                azimuth: azimuth,
                elevation: elevation,
                distance: distance,
                target: [target.x, target.y, target.z],
                yfov: look.fieldOfView * .pi / 180,
                znear: planes.near,
                zfar: planes.far
            ),
            sceneMin: sceneMin,
            sceneMax: sceneMax
        )
    }

    // MARK: - Input (from the view)

    func orbit(byX dx: Double, y dy: Double) {
        azimuth -= dx * 0.4
        elevation = min(89, max(-89, elevation + dy * 0.4))
        updateCamera()
    }

    func zoom(by factor: Double) {
        distance = min(max(distance * factor, boundingRadius * 0.05), boundingRadius * 100)
        updateCamera()
    }

    func autoRotateStep() {
        azimuth += 0.25
        updateCamera()
    }

    private static func toneMapper(_ mapping: RenderLook.ToneMapping) -> FLToneMapper {
        switch mapping {
        case .pbrNeutral: .pbrNeutral
        case .acesHill: .ACES
        case .acesNarkowicz: .acesLegacy
        default: .linear
        }
    }
}

/// Layer-backed `CAMetalLayer` view the live Filament swap chain draws into.
final class FilamentMetalView: NSView {
    weak var host: FilamentRendererHost?
    var autoRotates = false
    private var renderer: FLRenderer?
    private var link: CADisplayLink?
    private let started = CACurrentMediaTime()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    convenience init() { self.init(frame: NSRect(x: 0, y: 0, width: 512, height: 512)) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    var drawablePixels: (width: Int, height: Int) {
        let size = metalLayer?.drawableSize ?? .zero
        return (Int(size.width), Int(size.height))
    }

    func attach(_ renderer: FLRenderer) {
        self.renderer = renderer
        if let metalLayer { renderer.attach(metalLayer) }
        updateDrawableSize()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        updateDrawableSize()
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard let metalLayer else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        let pixels = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        if metalLayer.drawableSize != pixels {
            metalLayer.drawableSize = pixels
            host?.updateCamera()
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let renderer else { return }
        if autoRotates { host?.autoRotateStep() }
        let pixels = drawablePixels
        renderer.renderFrame(withWidth: pixels.width, height: pixels.height, time: CACurrentMediaTime() - started)
    }

    // MARK: Input

    /// Window-space pointer position at the last orbit step; nil when no orbit drag is active.
    private var orbitAnchor: NSPoint?

    override func mouseDown(with event: NSEvent) {
        orbitAnchor = event.locationInWindow
        super.mouseDown(with: event)
    }

    /// Orbits by the pointer's motion *within the window*. `event.deltaX/Y` is screen motion, so a
    /// title-band drag over the full-bleed canvas — which moves the window with the pointer — used
    /// to spin the camera too. Only a drag this view saw start orbits.
    override func mouseDragged(with event: NSEvent) {
        guard let anchor = orbitAnchor else { return }
        let location = event.locationInWindow
        orbitAnchor = location
        // Window space is y-up; `orbit` takes the y-down deltas `NSEvent.deltaY` reports.
        host?.orbit(byX: Double(location.x - anchor.x), y: Double(anchor.y - location.y))
    }

    override func mouseUp(with event: NSEvent) {
        orbitAnchor = nil
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        host?.zoom(by: exp(-Double(delta) * 0.01))
    }

    override func magnify(with event: NSEvent) {
        host?.zoom(by: exp(-Double(event.magnification)))
    }
}

private extension Duration {
    var milliseconds: Int {
        let parts = components
        return Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
    }
}
