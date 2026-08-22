import Foundation
import Observation

/// The per-window "how it is shown" state — what the canvas pills and the View menu drive.
/// Live and per-window: it never writes app defaults (DESIGN.md three-job rule).
@MainActor
protocol ViewportController: AnyObject, Observable {
    var backdrop: BackdropStyle { get }
    var showsFloor: Bool { get }
    var autoRotates: Bool { get }
    /// False reveals the authored origin (origin gizmo).
    var isCentered: Bool { get }
    var viewMode: ViewMode { get }
    var projection: Projection { get }
    var lighting: LightingSettings { get }
    /// Nil once the user orbits away from a preset.
    var activeCameraPreset: CameraPreset? { get }
    /// Scene the canvas is showing. Selecting a Scene row calls `setScene`.
    var activeSceneID: NodeID? { get }
    /// Selected `KHR_materials_variants` index, or nil for the file default.
    var selectedMaterialVariantIndex: Int? { get }

    func setBackdrop(_ style: BackdropStyle)
    func setFloor(_ isOn: Bool)
    func setAutoRotate(_ isOn: Bool)
    func setCenter(_ isOn: Bool)
    func setViewMode(_ mode: ViewMode)
    func setProjection(_ projection: Projection)
    func setLighting(_ lighting: LightingSettings)
    /// Frame the model in the current view.
    func fit()
    /// Back to the opening pose and view state.
    func reset()
    func applyCameraPreset(_ preset: CameraPreset)
    /// Capture the canvas. Fire-and-forget: the implementation owns where it lands.
    func screenshot()
    func setScene(_ id: NodeID)
    func setMaterialVariant(_ index: Int?)
}
