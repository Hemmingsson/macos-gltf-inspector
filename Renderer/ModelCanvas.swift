import AppKit
import GLTFCore
import GLTFKit2
import Observation
import SwiftUI
import simd

/// One loaded glTF animation clip exposed to the window (name and duration in seconds).
public struct AnimationClipDescriptor: Sendable, Equatable {
    public let name: String?
    public let duration: Float

    public init(name: String?, duration: Float) {
        self.name = name
        self.duration = duration
    }
}

/// The live model canvas of the document window and the Quick Look preview.
///
/// Its owner keeps the `ModelCanvasController`, which outlives a SwiftUI remount of this view:
/// the next mount adopts the running `ModelView` instead of loading the file again.
public struct ModelCanvas: View {
    let url: URL
    let options: ViewOptions
    let controller: ModelCanvasController

    public init(url: URL, options: ViewOptions, controller: ModelCanvasController) {
        self.url = url
        self.options = options
        self.controller = controller
    }

    public var body: some View {
        CanvasRepresentable(url: url, options: options, controller: controller)
            .overlay {
                if controller.phase == .loading {
                    ProgressView("Loading model…")
                        .controlSize(.small)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Loads a file into one `ModelView`, keeps its options in sync and reports how that went.
@MainActor
@Observable
public final class ModelCanvasController {
    public enum Phase: Equatable, Sendable {
        case loading
        /// The model is on screen.
        case ready
        /// The renderer could not start or the file could not be drawn. User-visible reason.
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    /// Increments after each successful file load or reload on the canvas view.
    public private(set) var sceneGeneration: Int = 0
    /// The loaded scene on the live canvas, for a preview view to adopt.
    public var scene: MetalScene? { view?.renderer.scene }
    /// Camera zoom against the last fit (100 = fitted). Nil before the first model is framed.
    public private(set) var zoomPercent: Int?
    /// Rotation of the current view matrix; updates when the camera moves.
    public private(set) var viewRotation = matrix_identity_float3x3
    /// Count of uncached `bounds(ofNode:)` evaluations since the last scene generation change.
    private(set) var boundsEvaluations = 0
    @ObservationIgnored private var boundsCache: [Int: (min: SIMD3<Float>, max: SIMD3<Float>)] = [:]
    @ObservationIgnored private var boundsCacheGeneration = -1

    @ObservationIgnored private(set) var view: ModelView?
    @ObservationIgnored private var reportedViewRotation = matrix_identity_float3x3
    /// The file and options SwiftUI last asked for; `sync` brings the view there.
    @ObservationIgnored private var wanted: (url: URL, options: ViewOptions)?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var isSyncing = false
    /// Points the sidebar and inspector cover at each side; see `ModelView.contentInsets`.
    @ObservationIgnored public var contentInsets = NSEdgeInsets() {
        didSet { view?.contentInsets = contentInsets }
    }
    /// Forwards to the live `ModelView` when mounted.
    @ObservationIgnored public var onPick: ((Int?) -> Void)? {
        didSet { view?.onPick = onPick }
    }
    /// ⌘- / ⇧-click on a node; forwards to the live `ModelView`.
    @ObservationIgnored public var onTogglePick: ((Int) -> Void)? {
        didSet { view?.onTogglePick = onTogglePick }
    }
    /// A pointer orbit drag started on the canvas (not a pan); forwards to the live `ModelView`.
    @ObservationIgnored public var onOrbitStart: (() -> Void)? {
        didSet { view?.onOrbitStart = onOrbitStart }
    }
    /// glTF node under the resting pointer, for the name tooltip and the layer-row tint.
    public private(set) var hoveredNode: Int?
    /// Pointer position for the tooltip: canvas view points, origin top-left.
    public private(set) var hoverLocation: CGPoint?

    // MARK: - Animation playback

    /// Clips in the loaded file; empty before the first successful load or when the file has none.
    public private(set) var animationClips: [AnimationClipDescriptor] = []
    /// Indices into `animationClips` / the loaded clip list that are evaluated together.
    public var selectedClipIndices: [Int] = [] {
        didSet { playbackStateDidChange() }
    }
    public private(set) var isPlaying = false
    /// Current time in seconds along the active clips; 0 at rest when the window opens.
    public var time: Float = 0
    public var loops = true
    /// Playback rate clamped to 0.25…2.
    public var speed: Float {
        get { storedSpeed }
        set { storedSpeed = Self.clampedSpeed(newValue) }
    }
    private var storedSpeed: Float = 1
    /// Stepped in tests; live windows use wall time between display-link ticks.
    public var playbackClock = AnimationPlaybackClock.live

    @ObservationIgnored private var loadedAnimationClips: [AnimationClip] = []
    @ObservationIgnored private var defaultSelectedClipIndices: [Int] = []
    @ObservationIgnored private var matrixAuthoredNodes: Set<Int> = []
    @ObservationIgnored private var lastPlaybackInstant: ContinuousClock.Instant?

    /// Longest active clip duration in seconds; 0 when nothing is selected.
    public var activePlaybackDuration: Float { playbackDuration }
    /// Disjoint clip set chosen on load (Khronos default).
    public var defaultSelectedAnimationClipIndices: [Int] { defaultSelectedClipIndices }

    public init() {}

    public func play() {
        guard !animationClips.isEmpty else { return }
        isPlaying = true
        lastPlaybackInstant = playbackClock.now()
        playbackStateDidChange()
    }

    public func pause() {
        guard isPlaying else { return }
        isPlaying = false
        lastPlaybackInstant = nil
        playbackStateDidChange()
    }

    /// Sets clip time in seconds and redraws; does not start playback.
    public func scrub(to seconds: Float) {
        time = max(0, seconds)
        if isPlaying { lastPlaybackInstant = playbackClock.now() }
        playbackStateDidChange()
    }

    /// Pauses and returns to rest pose (time 0). Clip selection is unchanged.
    public func stopPlayback() {
        isPlaying = false
        time = 0
        lastPlaybackInstant = nil
        playbackStateDidChange()
    }

    /// Khronos default: every disjoint clip in file order.
    public func selectDefaultAnimationClips() {
        guard !defaultSelectedClipIndices.isEmpty else { return }
        selectedClipIndices = defaultSelectedClipIndices
    }

    /// One clip, or the default disjoint set when `index` is nil.
    public func selectAnimationClip(at index: Int?) {
        if let index, loadedAnimationClips.indices.contains(index) {
            selectedClipIndices = [index]
        } else {
            selectDefaultAnimationClips()
        }
    }

    public func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    /// Scene-graph node indices targeted by the given clip indices (TRS and node weights).
    public func animatedSceneNodeIndices(forClipIndices indices: [Int]) -> Set<Int> {
        var nodes = Set<Int>()
        for index in indices where loadedAnimationClips.indices.contains(index) {
            for channel in loadedAnimationClips[index].channels {
                if let nodeIndex = channel.target.nodeIndexForMatrixSkip {
                    nodes.insert(nodeIndex)
                }
            }
        }
        return nodes
    }

    /// Scene-graph nodes animated by the currently selected clips.
    public func animatedSceneNodeIndicesInSelection() -> Set<Int> {
        animatedSceneNodeIndices(forClipIndices: selectedClipIndices)
    }

    /// Pose passed to the renderer for the current time and clip selection.
    public func currentAnimationPose() -> AnimationPose? {
        animationPoseForRender()
    }

    /// Seeds the wall-clock anchor used by the next display-link tick (unit tests only).
    func seedPlaybackInstantForTesting(_ instant: ContinuousClock.Instant) {
        lastPlaybackInstant = instant
    }

    /// Advances playback by `elapsed` seconds of clip time (honours `speed`). For unit tests.
    func advancePlayback(elapsed: Float) {
        guard isPlaying, !selectedClipIndices.isEmpty else { return }
        applyTimeDelta(elapsed * speed)
    }

    private static func clampedSpeed(_ value: Float) -> Float {
        min(max(value, 0.25), 2)
    }

    private var playbackDuration: Float {
        selectedClipIndices.compactMap { loadedAnimationClips.indices.contains($0) ? loadedAnimationClips[$0].maxTime : nil }.max() ?? 0
    }

    private func animationPoseForRender() -> AnimationPose? {
        let clips = selectedClipIndices.compactMap { loadedAnimationClips.indices.contains($0) ? loadedAnimationClips[$0] : nil }
        guard !clips.isEmpty else { return nil }
        if !isPlaying, time == 0 { return nil }
        return AnimationPose(clips: clips, at: time, matrixAuthoredNodes: matrixAuthoredNodes)
    }

    func tickAnimationFromDisplayLink() {
        guard isPlaying else { return }
        let now = playbackClock.now()
        defer { lastPlaybackInstant = now }
        guard let last = lastPlaybackInstant else { return }
        let span = last.duration(to: now)
        let elapsed = Float(Double(span.components.seconds) + Double(span.components.attoseconds) / 1e18)
        guard elapsed > 0 else { return }
        applyTimeDelta(elapsed * speed)
    }

    private func applyTimeDelta(_ delta: Float) {
        guard delta > 0 else { return }
        time += delta
        let duration = playbackDuration
        guard duration > 0, time >= duration else {
            playbackStateDidChange(redrawOnly: true)
            return
        }
        if loops {
            time = time.truncatingRemainder(dividingBy: duration)
        } else {
            time = duration
            isPlaying = false
            lastPlaybackInstant = nil
        }
        playbackStateDidChange()
    }

    private func reloadAnimationClips(from url: URL) {
        loadedAnimationClips = []
        defaultSelectedClipIndices = []
        matrixAuthoredNodes = []
        animationClips = []
        selectedClipIndices = []
        isPlaying = false
        time = 0
        lastPlaybackInstant = nil
        do {
            GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"
            let options: [GLTFAssetLoadingOption: Any] = [.assetDirectoryURLKey: url.deletingLastPathComponent()]
            let asset = try GLTFAsset(url: url, options: options)
            let clips = try AnimationClipLoader.loadClips(from: asset)
            loadedAnimationClips = clips
            matrixAuthoredNodes = AnimationClipLoader.matrixAuthoredNodeIndices(sourceURL: url)
            animationClips = clips.map { AnimationClipDescriptor(name: $0.name, duration: $0.maxTime) }
            defaultSelectedClipIndices = AnimationClip.defaultSelectedClipIndices(in: clips)
            selectedClipIndices = defaultSelectedClipIndices
        } catch {
            AppLog.error(AppLog.renderer, "animation clips failed \(url.lastPathComponent): \(error)")
        }
        playbackStateDidChange()
    }

    private func playbackStateDidChange(redrawOnly: Bool = false) {
        view?.isPlaybackRunning = isPlaying
        if !redrawOnly { view?.updateDisplayLink() }
        view?.redraw()
    }

    private func wirePlayback(on view: ModelView) {
        view.isPlaybackRunning = isPlaying
        view.onAnimationPlaybackStep = { [weak self] in self?.tickAnimationFromDisplayLink() }
        view.animationPoseProvider = { [weak self] in self?.animationPoseForRender() }
    }

    // MARK: - Camera commands

    public func fit() { readyView?.fit() }
    public func frame(nodeIndices: [Int]) { readyView?.frame(nodeIndices: nodeIndices) }
    public func show(_ preset: CameraPreset) { readyView?.show(preset) }
    public func zoom(by factor: Double) { readyView?.zoom(by: factor) }
    public func orbit(dx: Double, dy: Double) { readyView?.orbit(dx: dx, dy: dy) }

    /// World-space box of one node's subtree in the loaded scene, or nil before a load or for a
    /// node with no drawn geometry. Re-read when `sceneGeneration` changes.
    public func bounds(ofNode index: Int) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        if boundsCacheGeneration != sceneGeneration {
            boundsCache.removeAll(keepingCapacity: true)
            boundsCacheGeneration = sceneGeneration
            boundsEvaluations = 0
        }
        if let cached = boundsCache[index] { return cached }
        boundsEvaluations += 1
        guard let box = view?.renderer.scene?.bounds(ofNode: index) else { return nil }
        boundsCache[index] = box
        return box
    }

    /// One frame at the canvas's pixel size. The caller writes the file.
    public func snapshot() throws -> CGImage {
        guard let view = readyView else { throw MetalRendererError.noScene }
        return try view.snapshot()
    }

    /// The canvas's pixel size, for exports that match what is on screen.
    public var pixelSize: CGSize? {
        readyView?.drawablePixelSize
    }

    /// One 360° orbit as frames; see `ModelView.turntable`.
    public func turntable(count: Int, width: Int, height: Int,
                          frame: (Int, CGImage) async throws -> Void) async throws {
        guard let view = readyView else { throw MetalRendererError.noScene }
        try await view.turntable(count: count, width: width, height: height, frame: frame)
    }

    private var readyView: ModelView? { phase == .ready ? view : nil }

    // MARK: - Mounting

    /// Puts the model view in `container`, creating it on first use.
    func mount(in container: NSView, url: URL, options: ViewOptions) {
        if view == nil {
            do {
                let view = ModelView(renderer: try MetalRenderer())
                view.onZoom = { [weak self] in self?.zoomPercent = $0 }
                view.onFailure = { [weak self] in self?.fail($0) }
                view.onPick = onPick
                view.onTogglePick = onTogglePick
                view.onOrbitStart = onOrbitStart
                view.onHover = { [weak self] node, location in
                    guard let self else { return }
                    if hoveredNode != node { hoveredNode = node }
                    if hoverLocation != location { hoverLocation = location }
                }
                view.onOrientation = { [weak self] rotation in
                    guard let self, rotation != reportedViewRotation else { return }
                    reportedViewRotation = rotation
                    viewRotation = rotation
                }
                view.contentInsets = contentInsets
                wirePlayback(on: view)
                self.view = view
            } catch {
                loadedURL = url
                fail(error)
                return
            }
        }
        guard let view else { return }
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        update(url: url, options: options)
    }

    /// Runs on every SwiftUI update. Records what is wanted; one `sync` at a time does the work,
    /// so renderer calls never overlap and the latest request always wins.
    func update(url: URL, options: ViewOptions) {
        if wanted?.url == url, wanted?.options == options { return }
        wanted = (url, options)
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            await sync()
            isSyncing = false
        }
    }

    /// Loads the wanted file, then applies the wanted options, until the view matches both.
    /// A failed file stays failed until a different file is wanted.
    private func sync() async {
        while let view, let wanted {
            do {
                if wanted.url != loadedURL {
                    loadedURL = wanted.url
                    phase = .loading
                    let started = ContinuousClock.now
                    try await view.load(wanted.url, options: wanted.options)
                    guard self.wanted?.url == wanted.url else { continue }
                    reloadAnimationClips(from: wanted.url)
                    phase = .ready
                    sceneGeneration += 1
                    AppLog.info(AppLog.renderer, "canvas ready \(wanted.url.lastPathComponent) in \(started.duration(to: .now))")
                } else if case .failed = phase {
                    return
                } else if view.options != wanted.options {
                    let before = view.renderer.scene.map { ObjectIdentifier($0) }
                    try await view.apply(wanted.options)
                    if view.renderer.scene.map({ ObjectIdentifier($0) }) != before {
                        sceneGeneration += 1
                    }
                } else {
                    return
                }
            } catch {
                if self.wanted?.url != wanted.url { continue }
                if phase == .ready {
                    // An options change failed; the model drawn so far stays.
                    AppLog.error(AppLog.renderer, "canvas update failed \(wanted.url.lastPathComponent): \(error)")
                } else {
                    fail(error)
                }
                return
            }
        }
    }

    /// The owner routes on `phase` and swaps the canvas for its own failure view. The log keeps
    /// the raw error; the person sees a sentence.
    private func fail(_ error: Error) {
        AppLog.error(AppLog.renderer, "canvas failed \(loadedURL?.lastPathComponent ?? "-"): \(error)")
        phase = .failed(Self.message(for: error))
    }

    static func message(for error: Error) -> String {
        if case MetalRendererError.unavailable = error { return "This Mac can't run the Metal renderer." }
        return "The model couldn't be displayed. The file may be damaged or use features the renderer doesn't support."
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let url: URL
    let options: ViewOptions
    let controller: ModelCanvasController

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        controller.mount(in: container, url: url, options: options)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        controller.update(url: url, options: options)
    }
}
