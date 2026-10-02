import AppKit
import GLTFCore
import RealityKit
import simd
import SwiftUI

/// Host-only overlay applied during RealityView updates. Quick Look and thumbnails pass `nil`.
///
/// The host supplies plain values (selection, hide/solo, revision); the canvas applies them to its
/// entities through `applyIfNeeded(to:)`.
@MainActor
public protocol PreviewOverlay: AnyObject {
    var overlayRevision: Int { get }
    var selectedCameraIndex: Int? { get }
    var selectedNodeIndex: Int? { get }
    var document: GLTFSessionDocument { get }
    /// Which glTF nodes stay enabled.
    var nodeVisibility: PreviewNodeVisibility { get }
    /// Last `overlayRevision` applied to the canvas. Written by `applyIfNeeded(to:)` only.
    var appliedOverlayRevision: Int { get set }
}

/// Hide + solo as node-index sets.
public struct PreviewNodeVisibility: Equatable, Sendable {
    public var hidden: Set<Int> = []
    /// Nodes that stay enabled while solo is active; `nil` when not soloing.
    public var soloVisible: Set<Int>?

    public init(hidden: Set<Int> = [], soloVisible: Set<Int>? = nil) {
        self.hidden = hidden
        self.soloVisible = soloVisible
    }

    public func isEnabled(_ nodeIndex: Int) -> Bool {
        let hiddenBySolo = soloVisible.map { !$0.contains(nodeIndex) } ?? false
        return !hidden.contains(nodeIndex) && !hiddenBySolo
    }
}

extension PreviewOverlay {
    /// Visibility + selection chrome, once per `overlayRevision`.
    func applyIfNeeded(to root: Entity) {
        guard overlayRevision != appliedOverlayRevision else { return }
        appliedOverlayRevision = overlayRevision
        applyVisibility(nodeVisibility, to: root)
        PreviewSelectionVisuals.apply(selectedNodeIndex: selectedNodeIndex, to: root)
    }

    private func applyVisibility(_ visibility: PreviewNodeVisibility, to entity: Entity) {
        if let id = entity.components[GLTFNodeIDComponent.self]?.nodeIndex {
            entity.isEnabled = visibility.isEnabled(id)
        }
        for child in entity.children {
            applyVisibility(visibility, to: child)
        }
    }
}

/// Interaction model (Sketchfab / Three.js OrbitControls-style):
/// - Drag → system RealityKit `.orbit` around the turntable pivot (`orbitFocus`)
/// - Scroll / pinch → infinite dolly along the camera look axis
/// - Shift-drag → pan (camera + pivot move together in the view plane)
@Observable
public final class PreviewInteraction {
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

    public init() {}

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
    }

    /// Bumped from the View menu. `PreviewScene` applies opening fit on MainActor —
    /// never from RealityView `update`.
    private(set) var openingFitResetID = 0

    public func requestOpeningFitReset() {
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

    public func applyScroll(_ event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        guard dy != 0, didFit else { return }
        applyDolly(factor: exp(Float(dy) * -0.004))
    }

    public func applyMagnify(_ event: NSEvent) {
        guard event.magnification != 0, didFit else { return }
        applyDolly(factor: exp(Float(event.magnification) * -0.8))
    }

    private func endPointerGesture() {
        isCameraGesturing = false
        isPanning = false
        gestureBeganAt = nil
        lastPanWindowPoint = nil
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

extension PreviewInteraction {
    /// Fit the orbit camera to `model` (front-¾, or `preset`). Returns false when there is no
    /// live camera or nothing to frame; the interaction is marked fitted either way.
    @MainActor
    public func reframe(
        on model: EntityLoader.LoadedModel?,
        orthographic: Bool,
        preset: CameraPreset? = nil,
        fieldOfViewDegrees: Float
    ) -> Bool {
        guard let camera, let entity = model?.entity else {
            markFitted()
            return false
        }
        let bounds = PreviewCamera.modelBounds(of: entity, relativeTo: nil)
        guard !bounds.isEmpty else {
            markFitted()
            return false
        }
        if let preset {
            PreviewCamera.applyFit(
                to: camera,
                bounds: bounds,
                orbitFocus: orbitFocus,
                orthographic: orthographic,
                preset: preset,
                fieldOfViewInDegrees: fieldOfViewDegrees
            )
        } else {
            PreviewCamera.applyFit(
                to: camera,
                bounds: bounds,
                orbitFocus: orbitFocus,
                orthographic: orthographic,
                fieldOfViewInDegrees: fieldOfViewDegrees
            )
        }
        markFitted()
        return true
    }
}

/// Orbit-drag pause + Shift-pan (events swallowed so RealityKit does not orbit while panning).
enum PreviewOrbitDragMonitor {
    @MainActor
    static func install(
        on view: NSView,
        interaction: @escaping () -> PreviewInteraction?,
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
            let panning = interaction()?.isPanning == true
            // A full-bleed canvas sits *under* the sidebar / inspector / pills, so a bounds
            // check alone would swallow e.g. a Shift-click on a sidebar row as a pan. Only
            // take events whose topmost hit view is the canvas (or inside it); a pan that
            // already started keeps its drags/up wherever the pointer goes.
            let hitsCanvas = Self.topmostHit(for: event, in: view)
            if !hitsCanvas, !(panning && event.type != .leftMouseDown) {
                if event.type == .leftMouseUp {
                    interaction()?.notePointerUp()
                }
                return event
            }
            let shifting = event.modifierFlags.contains(.shift)
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

    /// `true` when the window's topmost view at the event location is `view` or a descendant.
    @MainActor
    static func topmostHit(for event: NSEvent, in view: NSView) -> Bool {
        guard let contentView = view.window?.contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hit = contentView.hitTest(point) else { return false }
        return hit === view || hit.isDescendant(of: view)
    }

    static func remove(_ storage: inout Any?) {
        if let storage {
            NSEvent.removeMonitor(storage)
        }
        storage = nil
    }
}
