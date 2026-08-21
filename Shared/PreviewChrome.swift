import AppKit
import RealityKit
import simd
import SwiftUI

/// Host-only overlay applied during RealityView updates. Quick Look and thumbnails pass `nil`.
@MainActor
protocol PreviewOverlay: AnyObject {
    var overlayRevision: Int { get }
    var selectedCameraIndex: Int? { get }
    var document: GLTFSessionDocument { get }
    func applyIfNeeded(to root: Entity)
}

/// Interaction model (Sketchfab / Three.js OrbitControls-style):
/// - Drag → system RealityKit `.orbit` around the turntable pivot (`orbitFocus`)
/// - Scroll / pinch → infinite dolly along the camera look axis
/// - Shift-drag → pan (camera + pivot move together in the view plane)
@Observable
final class PreviewInteraction {
    private(set) var didFit = false
    weak var camera: Entity?
    /// Orbit / pan target — the turntable pivot (`content.cameraTarget`).
    weak var orbitFocus: Entity?
    /// Orbit-drag only; scroll/pinch/pan leave the turntable running unless noted.
    private(set) var isCameraGesturing = false
    /// Shift-pan in progress (sticky until mouse-up even if Shift is released).
    private(set) var isPanning = false
    private var gestureBeganAt: Date?
    private var lastPanWindowPoint: CGPoint?
    private let gestureTimeout: TimeInterval = 2.5
    /// Floor so near-focus scroll ticks still advance instead of asymptoting.
    private let dollyKeepAhead: Float = 0.08

    var suppressesAutoRotate: Bool { isCameraGesturing }

    func refreshPointerTimeout() {
        guard isCameraGesturing, let began = gestureBeganAt,
              Date().timeIntervalSince(began) > gestureTimeout
        else { return }
        endPointerGesture()
    }

    @MainActor
    func markFitted() {
        didFit = true
        endPointerGesture()
        resetFOV()
    }

    /// Bumped from the View menu. `PreviewScene` applies opening fit on MainActor —
    /// never from RealityView `update`.
    private(set) var openingFitResetID = 0

    func requestOpeningFitReset() {
        openingFitResetID += 1
    }

    func bind(camera: Entity, orbitFocus: Entity) {
        self.camera = camera
        self.orbitFocus = orbitFocus
    }

    func noteOrbitDrag() {
        guard !isCameraGesturing else { return }
        gestureBeganAt = Date()
        isCameraGesturing = true
    }

    func notePointerUp() {
        endPointerGesture()
    }

    func beginPan(at windowPoint: CGPoint) {
        lastPanWindowPoint = windowPoint
        isPanning = true
        if !isCameraGesturing {
            gestureBeganAt = Date()
            isCameraGesturing = true
        }
    }

    func applyPan(to windowPoint: CGPoint) {
        guard didFit, let camera, let focus = orbitFocus else {
            lastPanWindowPoint = windowPoint
            return
        }
        defer { lastPanWindowPoint = windowPoint }
        guard let last = lastPanWindowPoint else { return }
        let dx = Float(windowPoint.x - last.x)
        let dy = Float(windowPoint.y - last.y)
        guard dx != 0 || dy != 0 else { return }

        let eye = camera.position(relativeTo: nil)
        let target = focus.position(relativeTo: nil)
        let dist = max(length(eye - target), 0.01)
        let sens = dist * 0.0018
        let rot = camera.orientation(relativeTo: nil)
        let right = rot.act(SIMD3<Float>(1, 0, 0))
        let up = rot.act(SIMD3<Float>(0, 1, 0))
        // Drag right → scene moves right (camera goes left), like OrbitControls.
        let delta = (-right * dx + up * dy) * sens
        guard delta.x.isFinite, delta.y.isFinite, delta.z.isFinite else { return }

        camera.setPosition(eye + delta, relativeTo: nil)
        // Pivot is the orbit target — moving it pans the model without a second focus entity.
        focus.setPosition(target + delta, relativeTo: nil)
        updateClip(eye: eye + delta, target: target + delta)
    }

    func applyScroll(_ event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        guard dy != 0, didFit else { return }
        applyDolly(factor: exp(Float(dy) * -0.004))
    }

    func applyMagnify(_ event: NSEvent) {
        guard event.magnification != 0, didFit else { return }
        applyDolly(factor: exp(Float(event.magnification) * -0.8))
    }

    private func endPointerGesture() {
        isCameraGesturing = false
        isPanning = false
        gestureBeganAt = nil
        lastPanWindowPoint = nil
    }

    @MainActor
    private func resetFOV() {
        guard let camera else { return }
        PreviewCamera.applyFieldOfView(to: camera, degrees: PreviewCamera.defaultFieldOfViewDegrees)
    }

    /// Dolly along the camera look axis (not eye→target). Factor &lt; 1 advances;
    /// can fly through the pivot and keep going — infinite dolly.
    private func applyDolly(factor: Float) {
        guard let camera, let focus = orbitFocus,
              factor.isFinite, factor > 0
        else { return }
        let eye = camera.position(relativeTo: nil)
        let target = focus.position(relativeTo: nil)
        let distance = length(target - eye)
        guard eye.x.isFinite, eye.y.isFinite, eye.z.isFinite else { return }
        let rot = camera.orientation(relativeTo: nil)
        let forward = rot.act(SIMD3<Float>(0, 0, -1))
        let travel = max(distance, dollyKeepAhead) * (1 - factor)
        let newEye = eye + forward * travel
        guard newEye.x.isFinite, newEye.y.isFinite, newEye.z.isFinite else { return }
        camera.setPosition(newEye, relativeTo: nil)
        updateClip(eye: newEye, target: target)
    }

    private func updateClip(eye: SIMD3<Float>, target: SIMD3<Float>) {
        guard let camera, var perspective = camera.components[PerspectiveCameraComponent.self] else { return }
        PreviewCamera.applyFitClip(to: &perspective, eye: eye, target: target)
        camera.components.set(perspective)
    }
}

/// Orbit-drag pause + Shift-pan (events swallowed so RealityKit does not orbit while panning).
enum PreviewOrbitDragMonitor {
    @MainActor
    static func install(
        on view: NSView,
        interaction: @escaping () -> PreviewInteraction?,
        hitTestBounds: Bool,
        storage: inout Any?
    ) {
        if let storage {
            NSEvent.removeMonitor(storage)
        }
        storage = nil
        guard view.window != nil else { return }
        storage = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { event in
            guard event.window === view.window else { return event }
            if hitTestBounds {
                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point) else {
                    if event.type == .leftMouseUp {
                        interaction()?.notePointerUp()
                    }
                    return event
                }
            }
            let shifting = event.modifierFlags.contains(.shift)
            let panning = interaction()?.isPanning == true
            switch event.type {
            case .leftMouseDown:
                if shifting {
                    interaction()?.beginPan(at: event.locationInWindow)
                    return nil
                }
            case .leftMouseDragged:
                if shifting || panning {
                    if !panning {
                        interaction()?.beginPan(at: event.locationInWindow)
                    }
                    interaction()?.applyPan(to: event.locationInWindow)
                    return nil
                }
                interaction()?.noteOrbitDrag()
            case .leftMouseUp:
                interaction()?.notePointerUp()
            default:
                break
            }
            return event
        }
    }

    static func remove(_ storage: inout Any?) {
        if let storage {
            NSEvent.removeMonitor(storage)
        }
        storage = nil
    }
}

/// Forwards trackpad scroll/magnify into `PreviewInteraction` (SwiftUI misses these on macOS).
final class PreviewHostingView: NSHostingView<PreviewView> {
    var interaction: PreviewInteraction?
    private var mouseMonitor: Any?

    required init(rootView: PreviewView) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { PreviewOrbitDragMonitor.remove(&mouseMonitor) }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        PreviewOrbitDragMonitor.install(
            on: self,
            interaction: { [weak self] in self?.interaction },
            hitTestBounds: true,
            storage: &mouseMonitor
        )
    }
}

/// Non-hosting root used by Quick Look so scroll events still hit before the hosting view.
/// Orbit/pan monitors stay on the nested `PreviewHostingView` only (one monitor per window).
final class PreviewEventView: NSView {
    var interaction: PreviewInteraction?

    override var isOpaque: Bool { false }
    override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
