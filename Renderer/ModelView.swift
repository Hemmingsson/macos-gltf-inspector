import AppKit
import GLTFCore
import Metal
import QuartzCore
import simd

/// One model drawn by the Metal renderer, with the Khronos orbit camera.
///
/// In a window it is the live canvas: it redraws on demand (input, option changes, resize) and
/// every display frame while auto-rotating. Off screen it renders stills (Finder thumbnails,
/// tests); the aspect it frames for is its `bounds`.
///
/// The camera follows the Khronos Sample Viewer: `MetalUserCamera` ports its `UserCamera` and
/// framing rules, and input maps to its pointer and wheel handlers.
@MainActor
public final class ModelView: NSView {
    public private(set) var options = ViewOptions()
    /// Zoom against the last fit as a whole percent (100 = fitted), each time it changes.
    public var onZoom: ((Int) -> Void)?
    /// A live frame failed to draw. The view stops drawing; its owner shows the failure.
    public var onFailure: ((Error) -> Void)?

    let renderer: MetalRenderer
    private(set) var camera = MetalUserCamera()
    private var modelURL: URL?
    /// Distance of the last front-view fit: 100% on the zoom readout.
    private var fitDistance: Double?
    private var reportedZoom: Int?
    private var drawFailed = false
    /// Points along each edge that window chrome covers. Left and right are the panes: the orbit
    /// camera centres and fits the model between them. Top is the title-bar band: a press there
    /// moves the window instead of the camera. The canvas itself still draws under all of it.
    public var contentInsets = NSEdgeInsets() {
        didSet {
            guard contentInsets.left != oldValue.left || contentInsets.right != oldValue.right else { return }
            redraw()
        }
    }
    private var displayLink: CADisplayLink?

    public init(renderer: MetalRenderer) {
        self.renderer = renderer
        super.init(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        wantsLayer = true
        metalLayer.device = renderer.device
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override public func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        return layer
    }

    // MARK: - Model and options

    /// Loads `url` drawn with `options` (the current ones when nil), frames it from the front and
    /// draws it. A file that fails to load leaves the previous model in place.
    public func load(_ url: URL, options next: ViewOptions? = nil) async throws {
        if let next {
            // The options are for the new file: do not reload the old one for a new scene.
            let previousURL = modelURL
            modelURL = nil
            defer { if modelURL == nil { modelURL = previousURL } }
            try await apply(next)
        }
        try await renderer.load(url: url, sceneIndex: options.sceneIndex == 0 ? nil : options.sceneIndex,
                                materialVariantIndex: options.materialVariantIndex)
        modelURL = url
        drawFailed = false
        fitCamera()
        redraw()
    }

    /// Cheap values are assigned; a scene or variant change reloads the model, and a scene or
    /// centring change refits, as the Khronos viewer does.
    public func apply(_ next: ViewOptions) async throws {
        let previous = options
        options = next
        if previous.fieldOfView != next.fieldOfView { camera.yfov = next.fieldOfView * .pi / 180 }
        camera.isOrthographic = next.isOrthographic
        let color = next.look.background
        metalLayer.backgroundColor = CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        updateDisplayLink()
        let sceneChanged = previous.sceneIndex != next.sceneIndex
        if let modelURL, sceneChanged || previous.materialVariantIndex != next.materialVariantIndex {
            try await renderer.load(url: modelURL, sceneIndex: next.sceneIndex == 0 ? nil : next.sceneIndex,
                                    materialVariantIndex: next.materialVariantIndex)
        }
        if renderer.scene != nil, sceneChanged || previous.isCentered != next.isCentered {
            fitCamera()
        } else if previous.isOrthographic != next.isOrthographic {
            camera.applyProjection()
        }
        redraw()
    }

    // MARK: - Camera commands

    /// Frames the model from the front.
    public func fit() {
        guard renderer.scene != nil else { return }
        fitCamera()
        orbit(azimuth: 0, elevation: 0)
        fitDistance = camera.distance
        redraw()
    }

    /// Frames the model from a canned angle.
    public func show(_ preset: CameraPreset) {
        guard renderer.scene != nil else { return }
        fitCamera()
        let angles = preset.angles
        let azimuth = angles.azimuth * .pi / 180, elevation = angles.elevation * .pi / 180
        let toCamera = SIMD3(sin(azimuth) * cos(elevation), -sin(elevation), cos(azimuth) * cos(elevation))
        let extent = camera.sceneMax - camera.sceneMin
        let measurable = simd_length(extent) > 0 && simd_length(extent).isFinite
        let distance = MetalUserCamera.sharedFitDistance(extent: extent, toCamera: toCamera, aspect: canvasAspect,
                                                         fieldOfViewDegrees: camera.yfov * 180 / .pi)
        orbit(azimuth: angles.azimuth, elevation: angles.elevation, distance: measurable ? distance : nil)
        redraw()
    }

    /// Dollies toward (`factor` < 1) or away from (`factor` > 1) the target at the current angle.
    public func zoom(by factor: Double) {
        guard renderer.scene != nil, factor > 0, camera.distance.isFinite else { return }
        orbit(azimuth: camera.rotAroundY * 180 / .pi, elevation: camera.rotAroundX * 180 / .pi,
              distance: camera.distance * factor)
        redraw()
    }

    /// Absolute orbit angles in degrees around the current target; nil keeps the distance.
    func orbit(azimuth: Double, elevation: Double, distance: Double? = nil) {
        camera.orbitTo(azimuth: azimuth, elevation: elevation, distance: distance ?? camera.distance, target: camera.target)
        camera.applyProjection()
    }

    /// Khronos `fitCamera` at the canvas aspect, for the current scene.
    private func fitCamera() {
        guard let scene = renderer.scene, let index = scene.gltfSceneIndex(for: options.sceneIndex) else { return }
        camera.isOrthographic = options.isOrthographic
        var extents = scene.accessorExtents(sceneIndex: index)
        // Draco replaces POSITION with an accessor without min/max; the decoded bounds are the same box.
        if !extents.min.x.isFinite || !extents.max.x.isFinite {
            extents = (SIMD3<Double>(scene.boundsMin), SIMD3<Double>(scene.boundsMax))
        }
        if let fitted = camera.fit(extents: extents, centered: options.isCentered, aspect: canvasAspect) {
            fitDistance = fitted
        }
    }

    /// The aspect of the uncovered part of the view, which the fit frames for.
    private var canvasAspect: Double {
        let width = bounds.width - contentInsets.left - contentInsets.right
        return bounds.height > 0 && width > 0 ? width / bounds.height : 1
    }

    /// Pixels the projection centre moves right so it sits mid-way between the panes. Off for a
    /// file camera, whose framing is authored.
    private func centerOffset(pixelWidth: Int) -> SIMD2<Float> {
        guard options.fileCameraNodeIndex == nil, bounds.width > 0 else { return .zero }
        let scale = Double(pixelWidth) / bounds.width
        return SIMD2(Float((contentInsets.left - contentInsets.right) / 2 * scale), 0)
    }

    // MARK: - Images

    /// One frame at `width`×`height` from the current camera.
    public func image(width: Int, height: Int, transmissionResolution: Int = 1024) throws -> CGImage {
        try renderer.image(options, pose: pose(width: width, height: height), width: width, height: height,
                           extents: extents, transmissionResolution: transmissionResolution)
    }

    /// One frame at the live canvas's pixel size (Export PNG).
    public func snapshot() throws -> CGImage {
        let size = metalLayer.drawableSize
        return try image(width: max(Int(size.width), 1), height: max(Int(size.height), 1))
    }

    /// Khronos `drawScene` records the canvas aspect on the orbit camera for every frame it draws.
    private func pose(width: Int, height: Int) -> MetalCameraPose {
        if options.fileCameraNodeIndex == nil { camera.aspectRatio = Double(width) / Double(height) }
        return camera.pose
    }

    /// The camera's measured box, which sizes the floor and origin gizmo.
    private var extents: (min: SIMD3<Float>, max: SIMD3<Float>) {
        (SIMD3<Float>(camera.sceneMin), SIMD3<Float>(camera.sceneMax))
    }

    // MARK: - Live drawing

    private func redraw() {
        reportZoom()
        guard window != nil, renderer.scene != nil, !drawFailed, let drawable = metalLayer.nextDrawable() else { return }
        do {
            let width = drawable.texture.width, height = drawable.texture.height
            let texture = try renderer.renderTexture(options, pose: pose(width: width, height: height),
                                                     width: width, height: height, extents: extents,
                                                     centerOffset: centerOffset(pixelWidth: width))
            try renderer.present(texture, on: drawable)
        } catch {
            drawFailed = true
            AppLog.error(AppLog.renderer, "draw failed: \(error.localizedDescription)")
            onFailure?(error)
        }
    }

    private func reportZoom() {
        guard renderer.scene != nil, let fitDistance, fitDistance > 0, camera.distance > 0 else { return }
        let percent = (fitDistance / camera.distance * 100).rounded()
        guard percent.isFinite, Int(percent) != reportedZoom else { return }
        reportedZoom = Int(percent)
        onZoom?(Int(percent))
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDisplayLink()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        redraw()
    }

    /// Auto-rotate turns the camera once per display frame, at the 60 Hz the Khronos viewer runs at.
    private func updateDisplayLink() {
        let wanted = options.autoRotates && window != nil
        guard wanted != (displayLink != nil) else { return }
        displayLink?.invalidate()
        displayLink = nil
        guard wanted else { return }
        let link = displayLink(target: self, selector: #selector(autoRotateStep))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func autoRotateStep() {
        guard renderer.scene != nil else { return }
        camera.orbit(1.2, 0)
        redraw()
    }

    // MARK: - Input: the Khronos viewer's pointer and wheel handlers

    /// Window-space pointer position at the last drag step; nil when no drag started in this
    /// view. `event.deltaX/Y` is screen motion, which also moves with a dragged window.
    private var dragAnchor: NSPoint?
    private var isPanning = false

    override public var acceptsFirstResponder: Bool { true }
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// The window moves only from the title-bar band (`mouseDown`), never with a camera drag.
    override public var mouseDownCanMoveWindow: Bool { false }

    override public func mouseDown(with event: NSEvent) {
        if isInTitleBarBand(event) {
            titleBarPress(event)
            return
        }
        beginDrag(event, pan: event.modifierFlags.contains(.shift))
    }

    private func isInTitleBarBand(_ event: NSEvent) -> Bool {
        guard contentInsets.top > 0 else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return (isFlipped ? point.y : bounds.height - point.y) < contentInsets.top
    }

    /// What the title bar does: drag moves the window, double-click runs the system action.
    private func titleBarPress(_ event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        } else {
            window.performDrag(with: event)
        }
    }
    override public func otherMouseDown(with event: NSEvent) { beginDrag(event, pan: event.buttonNumber == 2) }
    override public func mouseDragged(with event: NSEvent) { drag(event) }
    override public func otherMouseDragged(with event: NSEvent) { drag(event) }
    override public func mouseUp(with event: NSEvent) { dragAnchor = nil }
    override public func otherMouseUp(with event: NSEvent) { dragAnchor = nil }

    private func beginDrag(_ event: NSEvent, pan: Bool) {
        dragAnchor = event.locationInWindow
        isPanning = pan
    }

    /// `UserCamera.orbit(dx, dy)` or `pan(-dx, dy)`, in view points with y down.
    private func drag(_ event: NSEvent) {
        guard let start = dragAnchor, renderer.scene != nil else { return }
        let location = event.locationInWindow
        dragAnchor = location
        let dx = Double(location.x - start.x), dy = Double(start.y - location.y)
        if isPanning { camera.pan(-dx, dy) } else { camera.orbit(dx, dy) }
        redraw()
    }

    /// `UserCamera.zoomBy(deltaY * 0.01)`, with the browser wheel `deltaY` it was written for: the negated scroll delta
    /// in pixels, 40 per line step.
    override public func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 40
        wheel(deltaY: -Double(delta))
    }

    /// Pinch maps onto the same dolly as the wheel.
    override public func magnify(with event: NSEvent) {
        wheel(deltaY: -Double(event.magnification) * 500)
    }

    private func wheel(deltaY: Double) {
        guard renderer.scene != nil else { return }
        camera.zoomBy(deltaY * 0.01)
        redraw()
    }
}
