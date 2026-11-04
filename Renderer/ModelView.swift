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
    /// Unmodified left-click pick: glTF node index under the pointer, or nil for background.
    public var onPick: ((Int?) -> Void)?
    /// The first orbit step of a pointer drag (not a pan, not auto-rotate).
    public var onOrbitStart: (() -> Void)?
    /// ⌘- or ⇧-click on a node: add it to the selection or remove it. Background does nothing.
    public var onTogglePick: ((Int) -> Void)?
    /// The node under the resting pointer and where the pointer is (view points, y down), or
    /// (nil, nil) when it leaves the model, a drag starts or the pointer leaves the view.
    public var onHover: ((Int?, CGPoint?) -> Void)?
    /// Upper-left 3×3 of the view matrix used for the last draw (orbit or file camera).
    public var onOrientation: ((simd_float3x3) -> Void)?

    let renderer: MetalRenderer
    /// Transmission prepass size for live draws and snapshots from this view.
    public var transmissionResolution = 1024
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
    /// True while animation playback runs; keeps the display link alive with auto-rotate.
    var isPlaybackRunning = false
    var onAnimationPlaybackStep: (() -> Void)?
    var animationPoseProvider: (() -> AnimationPose?)?

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

    /// Draws an already-loaded scene (shared GPU buffers); frames and redraws like `load`.
    public func show(scene: MetalScene, options next: ViewOptions? = nil) throws {
        if let next { applyOptions(next) }
        modelURL = nil
        try renderer.adopt(scene)
        drawFailed = false
        fitCamera()
        redraw()
    }

    /// Cheap values are assigned; a scene or variant change reloads the model, and a scene or
    /// centring change refits, as the Khronos viewer does.
    public func apply(_ next: ViewOptions) async throws {
        let previous = options
        applyOptions(next)
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
        if !sceneChanged, next.orbitsAroundSelection, next.fileCameraNodeIndex == nil,
           let node = next.selectedNodeIndex, node != previous.selectedNodeIndex {
            retarget(toNode: node)
        }
        redraw()
    }

    private func applyOptions(_ next: ViewOptions) {
        let previous = options
        options = next
        if previous.fieldOfView != next.fieldOfView { camera.yfov = next.fieldOfView * .pi / 180 }
        camera.isOrthographic = next.isOrthographic
        let color = next.look.background
        metalLayer.backgroundColor = CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        updateDisplayLink()
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

    /// Frames one node's subtree at the current orbit angles (selection framing).
    public func frame(nodeIndex: Int) { frame(nodeIndices: [nodeIndex]) }

    /// Frames the union of several nodes' subtrees at the current orbit angles.
    public func frame(nodeIndices: [Int]) {
        guard let scene = renderer.scene else { return }
        let boxes = nodeIndices.compactMap { scene.bounds(ofNode: $0) }
        guard let first = boxes.first else { return }
        let box = boxes.dropFirst().reduce(first) { (simd_min($0.min, $1.min), simd_max($0.max, $1.max)) }
        cancelRetarget()
        camera.isOrthographic = options.isOrthographic
        if let framed = camera.frame(box: (SIMD3<Double>(box.min), SIMD3<Double>(box.max)), aspect: canvasAspect) {
            fitDistance = framed
        }
        redraw()
    }

    /// Front view fitted to one node's bounds.
    public func fit(nodeIndex: Int) {
        guard renderer.scene != nil else { return }
        frame(nodeIndex: nodeIndex)
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

    /// Khronos pointer orbit in view points (`UserCamera.orbit`).
    public func orbit(dx: Double, dy: Double) {
        guard renderer.scene != nil else { return }
        camera.orbit(dx, dy)
        camera.applyProjection()
        redraw()
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
                           extents: extents, transmissionResolution: transmissionResolution,
                           animationPose: animationPoseProvider?())
    }

    /// One full orbit around the current target for a turntable export: `count` frames at
    /// `width`×`height`, starting from the current angle. Each frame goes to `frame` as it is
    /// drawn (so a long export never holds every image), which may throw to stop. The live camera
    /// is left as it was.
    public func turntable(count: Int, width: Int, height: Int,
                          frame: (Int, CGImage) async throws -> Void) async throws {
        guard renderer.scene != nil, count > 0 else { throw MetalRendererError.noScene }
        // Orbits a copy, so live redraws during the export keep the person's view.
        var orbit = camera
        orbit.aspectRatio = Double(width) / Double(height)
        var turntableOptions = options
        turntableOptions.fileCameraNodeIndex = nil
        let azimuth = camera.rotAroundY * 180 / .pi, elevation = camera.rotAroundX * 180 / .pi
        for index in 0..<count {
            orbit.orbitTo(azimuth: azimuth + 360 * Double(index) / Double(count), elevation: elevation,
                          distance: camera.distance, target: camera.target)
            orbit.applyProjection()
            try await frame(index, renderer.image(turntableOptions, pose: orbit.pose, width: width, height: height,
                                                  extents: extents, transmissionResolution: transmissionResolution))
        }
    }

    /// The live canvas's size in pixels.
    public var drawablePixelSize: CGSize { metalLayer.drawableSize }

    /// One frame at the live canvas's pixel size (Export PNG).
    public func snapshot() throws -> CGImage {
        let size = metalLayer.drawableSize
        return try image(width: max(Int(size.width), 1), height: max(Int(size.height), 1),
                         transmissionResolution: transmissionResolution)
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

    /// Whether a live display link is installed (playback or auto-rotate).
    var isDisplayLinkActive: Bool { displayLink != nil }

    func redraw() {
        reportZoom()
        reportOrientation()
        guard window != nil, renderer.scene != nil, !drawFailed, let drawable = metalLayer.nextDrawable() else { return }
        do {
            let width = drawable.texture.width, height = drawable.texture.height
            var drawn = options
            drawn.hoveredNodeIndex = hoveredNode
            let texture = try renderer.renderTexture(drawn, pose: pose(width: width, height: height),
                                                     width: width, height: height, extents: extents,
                                                     transmissionResolution: transmissionResolution,
                                                     centerOffset: centerOffset(pixelWidth: width),
                                                     animationPose: animationPoseProvider?())
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

    private var reportedOrientation: simd_float3x3?

    private func reportOrientation() {
        guard renderer.scene != nil else { return }
        let size = metalLayer.drawableSize
        let width = max(Int(size.width), 1), height = max(Int(size.height), 1)
        let rotation = Self.rotation3x3(from: viewMatrix(width: width, height: height))
        guard rotation != reportedOrientation else { return }
        reportedOrientation = rotation
        onOrientation?(rotation)
    }

    private func viewMatrix(width: Int, height: Int) -> simd_float4x4 {
        if let index = options.fileCameraNodeIndex, let scene = renderer.scene,
           let fileCamera = scene.fileCamera(at: index, aspect: Float(width) / Float(height)) {
            return fileCamera.view
        }
        var camera = MetalCamera(pose: pose(width: width, height: height), isOrthographic: options.isOrthographic,
                                 aspect: Float(width) / Float(height))
        if centerOffset(pixelWidth: width) != .zero {
            let cameraViewport = khronosViewport(width: width, height: height, aspect: options.isOrthographic ? 1 : nil)
            let offset = centerOffset(pixelWidth: width)
            camera.centerShift = 2 * offset / SIMD2(Float(cameraViewport.width), Float(cameraViewport.height))
        }
        return camera.viewMatrix
    }

    static func rotation3x3(from viewMatrix: simd_float4x4) -> simd_float3x3 {
        simd_float3x3(columns: (
            SIMD3(viewMatrix.columns.0.x, viewMatrix.columns.0.y, viewMatrix.columns.0.z),
            SIMD3(viewMatrix.columns.1.x, viewMatrix.columns.1.y, viewMatrix.columns.1.z),
            SIMD3(viewMatrix.columns.2.x, viewMatrix.columns.2.y, viewMatrix.columns.2.z)
        ))
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

    /// Auto-rotate and animation playback share one display link at the Khronos viewer's 60 Hz.
    func updateDisplayLink() {
        let wanted = window != nil && (options.autoRotates || isPlaybackRunning)
        guard wanted != (displayLink != nil) else { return }
        displayLink?.invalidate()
        displayLink = nil
        guard wanted else { return }
        let link = displayLink(target: self, selector: #selector(displayLinkStep))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkStep() {
        guard renderer.scene != nil else { return }
        if options.autoRotates { camera.orbit(1.2, 0) }
        if isPlaybackRunning { onAnimationPlaybackStep?() }
        redraw()
    }

    // MARK: - Input: the Khronos viewer's pointer and wheel handlers

    /// Window-space pointer position at the last drag step; nil when no drag started in this
    /// view. `event.deltaX/Y` is screen motion, which also moves with a dragged window.
    private var dragAnchor: NSPoint?
    /// Window-space press location for click-vs-drag; unchanged while orbiting.
    private var pointerDownStart: NSPoint?
    private var pointerDownModifiers: NSEvent.ModifierFlags = []
    private var dragExceededClickThreshold = false
    private var isPanning = false
    private var didReportOrbit = false

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
    override public func mouseUp(with event: NSEvent) {
        performPickIfClick(with: event)
        dragAnchor = nil
        pointerDownStart = nil
    }
    override public func otherMouseUp(with event: NSEvent) {
        dragAnchor = nil
        pointerDownStart = nil
    }

    private func beginDrag(_ event: NSEvent, pan: Bool) {
        cancelRetarget()
        clearHover()
        let location = event.locationInWindow
        dragAnchor = location
        pointerDownStart = location
        pointerDownModifiers = event.modifierFlags
        dragExceededClickThreshold = false
        didReportOrbit = false
        isPanning = pan
    }

    private static let pickModifierMask: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// A press that never became a drag picks: plain → `onPick`, ⌘ or ⇧ alone → `onTogglePick`.
    /// ⌥ and ⌃ clicks pick nothing.
    private func performPickIfClick(with event: NSEvent) {
        guard let start = pointerDownStart, renderer.scene != nil, window != nil else { return }
        let modifiers = pointerDownModifiers.intersection(Self.pickModifierMask)
        let toggles = !modifiers.isEmpty && modifiers.isSubset(of: [.command, .shift])
        guard modifiers.isEmpty || toggles else { return }
        let end = event.locationInWindow
        guard !dragExceededClickThreshold, ModelViewPick.isClick(start: start, end: end) else { return }
        do {
            let index = try nodeIndex(atWindowPoint: end)
            if toggles {
                if let index { onTogglePick?(index) }
            } else {
                onPick?(index)
            }
        } catch {
            AppLog.error(AppLog.renderer, "pick failed: \(error.localizedDescription)")
        }
    }

    /// Camera / light gizmo under the point when they are drawn, else the mesh node under it.
    private func nodeIndex(atWindowPoint location: NSPoint) throws -> Int? {
        let viewPoint = convert(location, from: nil)
        let yDown = isFlipped ? viewPoint.y : bounds.height - viewPoint.y
        let (width, height, scale) = pickPixelSize
        let point = SIMD2(min(max(Int(viewPoint.x * scale), 0), width - 1),
                          min(max(Int(yDown * scale), 0), height - 1))
        let pointPoints = SIMD2(Float(viewPoint.x), Float(yDown))
        if options.showsSceneGizmos, let scene = renderer.scene {
            let center = centerOffset(pixelWidth: width)
            let frame = try renderer.gizmoPickFrame(options: options, pose: pose(width: width, height: height),
                                                    width: width, height: height, centerOffset: center)
            let overlayOptions = MetalOverlayOptions(options, canvasAspect: Float(width) / Float(height), extents: extents)
            let segments = overlayGizmoSegments(scene: scene, options: overlayOptions)
            let hitViewport = GizmoHitViewport(viewWidthPoints: Float(bounds.width),
                                               viewHeightPoints: Float(bounds.height),
                                               contentAspect: frame.viewportAspect)
            if let node = gizmoHit(at: pointPoints, segments: segments, viewProjection: frame.viewProjection,
                                   viewport: hitViewport) {
                return node
            }
        }
        return try renderer.pick(options, pose: pose(width: width, height: height),
                                 width: width, height: height,
                                 centerOffset: centerOffset(pixelWidth: width),
                                 point: point,
                                 animationPose: animationPoseProvider?())
    }

    /// The canvas's pixel size and backing scale, as picking and pointer zoom measure it.
    private var pickPixelSize: (width: Int, height: Int, scale: CGFloat) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return (max(Int((bounds.width * scale).rounded()), 1), max(Int((bounds.height * scale).rounded()), 1), scale)
    }

    /// World point under a view point (y down) on the plane through the orbit target that faces
    /// the camera. Nil for a file camera or when the ray misses the plane.
    private func pointerWorldPoint(atViewPoint viewPoint: NSPoint) -> SIMD3<Double>? {
        guard options.fileCameraNodeIndex == nil, renderer.scene != nil, bounds.width > 0, bounds.height > 0 else { return nil }
        let (width, height, _) = pickPixelSize
        guard let frame = try? renderer.gizmoPickFrame(options: options, pose: pose(width: width, height: height),
                                                       width: width, height: height,
                                                       centerOffset: centerOffset(pixelWidth: width)) else { return nil }
        let viewport = GizmoHitViewport(viewWidthPoints: Float(bounds.width), viewHeightPoints: Float(bounds.height),
                                        contentAspect: frame.viewportAspect)
        let yDown = Float(isFlipped ? viewPoint.y : bounds.height - viewPoint.y)
        let ndc = SIMD2((Float(viewPoint.x) - viewport.originX) / viewport.contentWidth * 2 - 1,
                        ((viewport.height - yDown) - viewport.originYFromBottom) / viewport.contentHeight * 2 - 1)
        let inverse = frame.viewProjection.inverse
        func unproject(_ z: Float) -> SIMD3<Double> {
            let p = inverse * SIMD4(ndc.x, ndc.y, z, 1)
            return SIMD3<Double>(SIMD3(p.x, p.y, p.z) / p.w)
        }
        let near = unproject(-1), far = unproject(1)
        let direction = far - near
        let normal = camera.lookDirection
        let denominator = simd_dot(direction, normal)
        guard abs(denominator) > 1e-12 else { return nil }
        let t = simd_dot(camera.target - near, normal) / denominator
        let point = near + direction * t
        return point.x.isFinite && point.y.isFinite && point.z.isFinite ? point : nil
    }

    // MARK: - Orbit pivot on the selection

    private var retargetTask: Task<Void, Never>?
    /// Seconds the pivot takes to glide onto a newly selected node. Zero jumps (tests).
    public var retargetDuration = 0.25

    /// Eases the orbit target onto the node's box centre while the eye stays put.
    private func retarget(toNode node: Int) {
        guard let box = renderer.scene?.bounds(ofNode: node) else { return }
        let goal = SIMD3<Double>((box.min + box.max) / 2)
        let from = camera.target
        guard simd_distance(from, goal) > 1e-9 else { return }
        cancelRetarget()
        guard retargetDuration > 0, window != nil else {
            camera.retargetKeepingEye(to: goal)
            camera.applyProjection()
            return
        }
        let duration = retargetDuration
        retargetTask = Task { @MainActor [weak self] in
            let started = ContinuousClock.now
            while let self, !Task.isCancelled {
                let elapsed = started.duration(to: .now)
                let t = min(Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds), duration) / duration
                let eased = t * t * (3 - 2 * t)
                self.camera.retargetKeepingEye(to: from + (goal - from) * eased)
                self.camera.applyProjection()
                self.redraw()
                if t >= 1 { self.retargetTask = nil; break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func cancelRetarget() {
        retargetTask?.cancel()
        retargetTask = nil
    }

    /// `UserCamera.orbit(dx, dy)` or `pan(-dx, dy)`, in view points with y down.
    private func drag(_ event: NSEvent) {
        guard let start = dragAnchor, renderer.scene != nil else { return }
        let location = event.locationInWindow
        dragAnchor = location
        let dx = Double(location.x - start.x), dy = Double(start.y - location.y)
        if let press = pointerDownStart,
           !ModelViewPick.isClick(start: press, end: location) { dragExceededClickThreshold = true }
        if isPanning {
            camera.pan(-dx, dy)
        } else {
            if !didReportOrbit, dx != 0 || dy != 0 {
                didReportOrbit = true
                onOrbitStart?()
            }
            camera.orbit(dx, dy)
        }
        redraw()
    }

    /// `UserCamera.zoomBy(deltaY * 0.01)`, with the browser wheel `deltaY` it was written for: the negated scroll delta
    /// in pixels, 40 per line step.
    override public func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 40
        wheel(deltaY: -Double(delta), at: event.locationInWindow)
    }

    /// Pinch maps onto the same dolly as the wheel.
    override public func magnify(with event: NSEvent) {
        wheel(deltaY: -Double(event.magnification) * 500, at: event.locationInWindow)
    }

    /// With `zoomsTowardPointer` (perspective only: the Khronos wheel keeps the orthographic
    /// scale) the dolly heads for the spot under the pointer instead of the orbit target.
    private func wheel(deltaY: Double, at windowPoint: NSPoint) {
        guard renderer.scene != nil else { return }
        cancelRetarget()
        if options.zoomsTowardPointer, !options.isOrthographic,
           let pointer = pointerWorldPoint(atViewPoint: convert(windowPoint, from: nil)) {
            camera.zoomBy(deltaY * 0.01, toward: pointer)
        } else {
            camera.zoomBy(deltaY * 0.01)
        }
        redraw()
    }

    // MARK: - Hover pre-selection

    private var hoverThrottle = HoverPickThrottle()
    private var hoverPending = false
    private var hoverPoint: NSPoint?
    private var hoveredNode: Int?
    private var hoverTrackingArea: NSTrackingArea?

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override public func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard onHover != nil, renderer.scene != nil, !isInTitleBarBand(event) else { return clearHover() }
        hoverPoint = event.locationInWindow
        let isBusy = dragAnchor != nil || options.autoRotates || isPlaybackRunning || retargetTask != nil
        guard !hoverPending, let delay = hoverThrottle.delay(at: CACurrentMediaTime(), isBusy: isBusy) else {
            if isBusy { clearHover() }
            return
        }
        hoverPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.pickHover() }
    }

    override public func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverPoint = nil
        clearHover()
    }

    private func pickHover() {
        hoverPending = false
        hoverThrottle.didPick(at: CACurrentMediaTime())
        guard let location = hoverPoint, dragAnchor == nil, window != nil else { return }
        let index = (try? nodeIndex(atWindowPoint: location)) ?? nil
        let viewPoint = convert(location, from: nil)
        let point = CGPoint(x: viewPoint.x, y: isFlipped ? viewPoint.y : bounds.height - viewPoint.y)
        onHover?(index, index == nil ? nil : point)
        guard index != hoveredNode else { return }
        hoveredNode = index
        redraw()
    }

    private func clearHover() {
        hoverPoint = nil
        guard hoveredNode != nil else { return }
        hoveredNode = nil
        onHover?(nil, nil)
        redraw()
    }
}
