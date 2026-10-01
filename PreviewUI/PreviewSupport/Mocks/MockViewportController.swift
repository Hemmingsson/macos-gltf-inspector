import Foundation
import Observation

/// Dev-time `ViewportController` for `#Preview` — neutral session state, no-op canvas actions.
@MainActor
@Observable
public final class MockViewportController: ViewportController {
    public private(set) var backdrop: BackdropStyle
    public private(set) var showsFloor: Bool
    public private(set) var autoRotates: Bool
    public private(set) var isCentered: Bool
    public private(set) var viewMode: ViewMode
    public private(set) var projection: Projection
    public private(set) var lighting: LightingSettings
    public private(set) var fieldOfViewDegrees: Float
    public private(set) var activeCameraPreset: CameraPreset?
    public private(set) var activeSceneID: NodeID?
    public private(set) var selectedMaterialVariantIndex: Int?

    public init(
        backdrop: BackdropStyle = .window,
        showsFloor: Bool = true,
        autoRotates: Bool = false,
        isCentered: Bool = true,
        viewMode: ViewMode = .shaded,
        projection: Projection = .perspective,
        lighting: LightingSettings = .standard,
        fieldOfViewDegrees: Float = 60,
        activeCameraPreset: CameraPreset? = nil,
        activeSceneID: NodeID? = NodeID(kind: .scene, index: 0),
        selectedMaterialVariantIndex: Int? = nil
    ) {
        self.backdrop = backdrop
        self.showsFloor = showsFloor
        self.autoRotates = autoRotates
        self.isCentered = isCentered
        self.viewMode = viewMode
        self.projection = projection
        self.lighting = lighting
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.activeCameraPreset = activeCameraPreset
        self.activeSceneID = activeSceneID
        self.selectedMaterialVariantIndex = selectedMaterialVariantIndex
    }

    public func setBackdrop(_ style: BackdropStyle) { backdrop = style }
    public func setFloor(_ isOn: Bool) { showsFloor = isOn }
    public func setAutoRotate(_ isOn: Bool) { autoRotates = isOn }
    public func setCenter(_ isOn: Bool) { isCentered = isOn }
    public func setViewMode(_ mode: ViewMode) { viewMode = mode }
    public func setProjection(_ projection: Projection) { self.projection = projection }
    public func setLighting(_ lighting: LightingSettings) { self.lighting = lighting }
    public func setFieldOfViewDegrees(_ degrees: Float) { fieldOfViewDegrees = degrees }

    public func fit() {}
    public func reset() {}
    public func applyCameraPreset(_ preset: CameraPreset) { activeCameraPreset = preset }
    public func screenshot() {}
    public func setScene(_ id: NodeID) { activeSceneID = id }
    public func setMaterialVariant(_ index: Int?) { selectedMaterialVariantIndex = index }
    public func setFileCamera(_ id: NodeID?) {
        if id == nil {
            activeCameraPreset = nil
        }
    }
}
