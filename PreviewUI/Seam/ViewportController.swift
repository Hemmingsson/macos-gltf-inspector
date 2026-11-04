import Foundation
import Observation

/// The per-window "how it is shown" state — what the canvas clusters and the View menu drive.
/// Live and per-window: it never writes app defaults (DESIGN.md three-job rule).
@MainActor
public protocol ViewportController: AnyObject, Observable {
    var backdrop: BackdropStyle { get }
    var showsFloor: Bool { get }
    var autoRotates: Bool { get }
    /// False reveals the authored origin (origin gizmo).
    var isCentered: Bool { get }
    var viewMode: ViewMode { get }
    var projection: Projection { get }
    var lighting: LightingSettings { get }
    /// Vertical field of view in degrees (perspective only).
    var fieldOfViewDegrees: Float { get }
    /// Nil once the user orbits away from a preset.
    var activeCameraPreset: CameraPreset? { get }
    /// Scene the canvas is showing. Selecting a Scene row calls `setScene`.
    var activeSceneID: NodeID? { get }
    /// Camera zoom against the last fit (100 = fitted), for the View menu's readout. Nil before
    /// the canvas has framed a model.
    var zoomPercent: Int? { get }
    /// Selected `KHR_materials_variants` index, or nil for the file default.
    var selectedMaterialVariantIndex: Int? { get }

    func setBackdrop(_ style: BackdropStyle)
    func setFloor(_ isOn: Bool)
    func setAutoRotate(_ isOn: Bool)
    func setCenter(_ isOn: Bool)
    func setViewMode(_ mode: ViewMode)
    func setProjection(_ projection: Projection)
    func setLighting(_ lighting: LightingSettings)
    func setFieldOfViewDegrees(_ degrees: Float)
    /// Frame the model in the current view.
    func fit()
    /// Move the camera closer (`factor` < 1) or farther (`factor` > 1) at the same angle.
    func zoom(by factor: Double)
    func applyCameraPreset(_ preset: CameraPreset)
    func setScene(_ id: NodeID)
    func setMaterialVariant(_ index: Int?)
    /// Activate a file camera (`NodeID.kind == .camera`, index of the outliner node that carries it).
    /// Pass `nil` to return to Fit / system orbit.
    func setFileCamera(_ id: NodeID?)
}
