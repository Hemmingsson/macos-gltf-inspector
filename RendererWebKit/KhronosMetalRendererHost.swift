import AppKit
import GLTFCore
import ImageIO
import Metal
import QuartzCore
import RendererMetal
import UniformTypeIdentifiers
import simd

/// Native hand port behind the same seam used by window, Quick Look, and thumbnails.
/// The default renderer for all three surfaces (`CanvasRenderer.makeHost`); `GLTF_RENDERER`
/// selects Filament or the WebKit page instead.
@MainActor
public final class KhronosMetalRendererHost: CanvasRendererHost {
    private let mode: WebRendererMode
    private let size: Int
    private var renderer: MetalRenderer?
    private let metalView = KhronosMetalView()
    private var look = WebPreviewCanvas.Look()
    private var modelURL: URL?
    private var pose = MetalCameraPose(azimuth: 0, elevation: 0, distance: 1, target: .zero,
                                       yfov: .pi / 4, znear: 0.01, zfar: 100)
    private var fitDistance = 1.0
    public private(set) var isBroken = false
    public var onFailure: ((WebRendererError) -> Void)?
    public var onZoom: ((Int) -> Void)?
    public var view: NSView { metalView }
    public var rendererName: String { "Metal · Khronos 863b981" }
    public var logID: String { "mtl-" + String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 36) }

    public init(mode: WebRendererMode, size: Int = 512) {
        self.mode = mode
        self.size = size
        metalView.host = self
    }
    public func start() async throws {
        // A broken host starts over, so the canvas's one restart per model can redraw it.
        guard renderer == nil || isBroken else { return }
        do {
            renderer = try MetalRenderer()
        } catch {
            throw WebRendererError.navigationFailed(error.localizedDescription)
        }
        isBroken = false
        metalView.metalLayer.device = renderer?.device
    }
    public func apply(_ look: WebPreviewCanvas.Look) async throws {
        try await start()
        let reload = self.look.sceneIndex != look.sceneIndex || self.look.materialVariantIndex != look.materialVariantIndex
        let refit = self.look.isCentered != look.isCentered
        self.look = look
        pose.yfov = look.fieldOfView * .pi / 180
        if reload, let modelURL { _ = try await load(model: modelURL) }
        else if refit { fit() }
        metalView.autoRotates = look.autoRotates
        redraw()
    }
    @discardableResult public func load(model url: URL) async throws -> WebRendererHost.LoadInfo {
        try await start()
        guard let renderer else { throw WebRendererError.notReady }
        let began = CFAbsoluteTimeGetCurrent()
        do {
            try await renderer.load(url: url, sceneIndex: look.sceneIndex == 0 ? nil : look.sceneIndex,
                                    materialVariantIndex: look.materialVariantIndex)
        } catch let error as WebRendererError {
            throw error
        } catch {
            // Same user-facing copy as the other backends for a file the renderer rejects.
            throw WebRendererError.callFailed("open: \(error.localizedDescription)")
        }
        modelURL = url
        fit()
        redraw()
        guard let scene = renderer.scene else { throw WebRendererError.notReady }
        return WebRendererHost.LoadInfo(triangles: scene.triangleCount, meshes: scene.draws.count,
            width: size, height: size, parseMs: Int((CFAbsoluteTimeGetCurrent() - began) * 1000), firstFrameMs: 0)
    }
    @discardableResult public func camera(_ command: CameraCommand) async throws -> RendererCameraState {
        switch command.op {
        case "fit": fit()
        case "orbit":
            pose.azimuth = command.azimuth ?? pose.azimuth
            pose.elevation = command.elevation ?? pose.elevation
            pose.distance = command.distance ?? pose.distance
        case "pose":
            if let p = command.pose, p.target.count == 3 {
                pose = MetalCameraPose(azimuth: p.azimuth, elevation: p.elevation, distance: p.distance,
                    target: SIMD3(Float(p.target[0]), Float(p.target[1]), Float(p.target[2])),
                    yfov: p.yfov, znear: p.znear, zfar: p.zfar)
            }
        default: break
        }
        redraw()
        return state
    }
    public func renderStill(size: Int? = nil) async throws -> CGImage {
        guard let renderer else { throw WebRendererError.notReady }
        // No size: a live canvas exports at its drawable size (Export PNG), a still at `self.size`.
        let drawable = metalView.metalLayer.drawableSize
        let (width, height) = if let size {
            (size, size)
        } else if mode == .live, drawable.width >= 1, drawable.height >= 1 {
            (Int(drawable.width), Int(drawable.height))
        } else {
            (self.size, self.size)
        }
        return try renderer.image(look: look.render, pose: pose, width: width, height: height,
                                  orthographic: look.isOrthographic, debugOutput: debugOutput,
                                  wireframe: look.viewMode == .wireframe,
                                  overlays: MetalOverlayOptions(floor: look.showsFloor, origin: !look.isCentered, selectedNode: look.selectedNodeIndex), fileCameraNodeIndex: look.fileCameraNodeIndex)
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
    private func fit() {
        guard let scene = renderer?.scene else { return }
        let low = scene.boundsMin, high = scene.boundsMax
        pose.target = look.isCentered ? (low + high) / 2 : .zero
        pose.azimuth = 0
        pose.elevation = 0
        let extent = high - low
        pose.distance = Double(RenderCamera.fitDistance(extent: extent, toCamera: SIMD3(0, 0, 1),
            aspect: Float(max(metalView.bounds.width, 1) / max(metalView.bounds.height, 1)),
            fieldOfViewInDegrees: Float(look.fieldOfView)))
        fitDistance = pose.distance
        let radius = Double(simd_length(extent) / 2)
        pose.znear = max(pose.distance - radius * 4, pose.distance * 0.001, 0.0001)
        pose.zfar = pose.distance + radius * 8
    }
    private var state: RendererCameraState {
        let low = renderer?.scene?.boundsMin ?? .zero
        let high = renderer?.scene?.boundsMax ?? .zero
        return RendererCameraState(pose: CameraPose(azimuth: pose.azimuth, elevation: pose.elevation,
            distance: pose.distance, target: [Double(pose.target.x), Double(pose.target.y), Double(pose.target.z)],
            yfov: pose.yfov, znear: pose.znear, zfar: pose.zfar),
            sceneMin: [Double(low.x), Double(low.y), Double(low.z)], sceneMax: [Double(high.x), Double(high.y), Double(high.z)])
    }
    func redraw() {
        guard mode == .live, metalView.window != nil, let renderer, renderer.scene != nil, !isBroken,
              let drawable = metalView.metalLayer.nextDrawable() else { return }
        do {
            let texture = try renderer.renderTexture(look: look.render, pose: pose,
                width: drawable.texture.width, height: drawable.texture.height,
                orthographic: look.isOrthographic, debugOutput: debugOutput, wireframe: look.viewMode == .wireframe,
                                  overlays: MetalOverlayOptions(floor: look.showsFloor, origin: !look.isCentered, selectedNode: look.selectedNodeIndex), fileCameraNodeIndex: look.fileCameraNodeIndex)
            try renderer.present(texture, on: drawable)
        } catch {
            isBroken = true
            onFailure?(.callFailed(error.localizedDescription))
        }
    }
    func orbit(dx: Double, dy: Double, pan: Bool = false) {
        if pan {
            let camera = MetalCamera(pose: pose)
            let scale = Float(2 * pose.distance * tan(pose.yfov / 2) / max(metalView.bounds.height, 1))
            let right = SIMD3(camera.transformMatrix.columns.0.x, camera.transformMatrix.columns.0.y, camera.transformMatrix.columns.0.z)
            let up = SIMD3(camera.transformMatrix.columns.1.x, camera.transformMatrix.columns.1.y, camera.transformMatrix.columns.1.z)
            pose.target += (-Float(dx) * right + Float(dy) * up) * scale
        } else {
            pose.azimuth -= dx * 0.4
            pose.elevation = min(89.9, max(-89.9, pose.elevation + dy * 0.4))
        }
        redraw()
    }
    func zoom(factor: Double) {
        pose.distance *= factor
        onZoom?(Int((fitDistance / pose.distance * 100).rounded()))
        redraw()
    }
    func rotate() { pose.azimuth += 0.25; redraw() }
}

@MainActor
private final class KhronosMetalView: NSView {
    weak var host: KhronosMetalRendererHost?
    var autoRotates = false { didSet { updateLink() } }
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
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        host?.redraw()
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsLayout = true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateLink(); host?.redraw() }
    private func updateLink() {
        link?.invalidate(); link = nil
        guard autoRotates, window != nil else { return }
        let l = displayLink(target: self, selector: #selector(step))
        l.add(to: .main, forMode: .common)
        link = l
    }
    @objc private func step() { host?.rotate() }
    override func mouseDragged(with event: NSEvent) { host?.orbit(dx: event.deltaX, dy: event.deltaY, pan: event.modifierFlags.contains(.shift)) }
    override func otherMouseDragged(with event: NSEvent) { host?.orbit(dx: event.deltaX, dy: event.deltaY, pan: true) }
    override func scrollWheel(with event: NSEvent) { host?.zoom(factor: exp(-event.scrollingDeltaY * 0.01)) }
    override func magnify(with event: NSEvent) { host?.zoom(factor: exp(-Double(event.magnification))) }
}
