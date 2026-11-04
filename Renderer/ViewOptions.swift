import Foundation
import GLTFCore

/// Everything a model is drawn with besides the file: the lighting look plus the view state.
/// The defaults are the Khronos viewer's opening state, so `ViewOptions()` adds no floor or
/// overlays (thumbnails, reference images).
public struct ViewOptions: Equatable, Sendable {
    public var look: RenderLook
    public var viewMode: RenderViewMode
    public var autoRotates: Bool
    public var isOrthographic: Bool
    /// Vertical field of view in degrees.
    public var fieldOfView: Double
    /// glTF node index of a camera authored in the file, or nil for the orbit camera.
    public var fileCameraNodeIndex: Int?
    /// `KHR_materials_variants` index, or nil for the file default.
    public var materialVariantIndex: Int?
    /// Scene index; 0 keeps the file's default scene.
    public var sceneIndex: Int
    public var showsFloor: Bool
    /// False frames the authored origin too and draws the origin gizmo.
    public var isCentered: Bool
    /// glTF node index whose bounding box is outlined.
    public var selectedNodeIndex: Int?

    public init(
        look: RenderLook = .standard,
        viewMode: RenderViewMode = .shaded,
        autoRotates: Bool = false,
        isOrthographic: Bool = false,
        fieldOfView: Double = 45,
        fileCameraNodeIndex: Int? = nil,
        materialVariantIndex: Int? = nil,
        sceneIndex: Int = 0,
        showsFloor: Bool = false,
        isCentered: Bool = true,
        selectedNodeIndex: Int? = nil
    ) {
        self.look = look
        self.viewMode = viewMode
        self.autoRotates = autoRotates
        self.isOrthographic = isOrthographic
        self.fieldOfView = fieldOfView
        self.fileCameraNodeIndex = fileCameraNodeIndex
        self.materialVariantIndex = materialVariantIndex
        self.sceneIndex = sceneIndex
        self.showsFloor = showsFloor
        self.isCentered = isCentered
        self.selectedNodeIndex = selectedNodeIndex
    }

    /// The look Settings stored in the App Group. Quick Look and the Finder thumbnail have no
    /// window state of their own, so both start here and light a file the same way.
    public static func stored(showsFloor: Bool = false, defaults: UserDefaults = AppGroupSettings.defaults) -> Self {
        Self(look: AppGroupSettings.rendererLook(defaults: defaults), showsFloor: showsFloor)
    }
}

/// Canned orbit angles. File cameras are separate.
public enum CameraPreset: String, Sendable, Hashable, CaseIterable {
    case front, back, left, right, top, bottom, isometric

    /// Khronos `UserCamera` angles in degrees: the eye sits at `R_y(azimuth) · R_x(elevation) ·
    /// (0, 0, +d)`, so azimuth +90 looks from +X and a negative elevation looks from above.
    var angles: (azimuth: Double, elevation: Double) {
        switch self {
        case .front: (0, 0)
        case .back: (180, 0)
        case .right: (90, 0)
        case .left: (-90, 0)
        case .top: (0, -90)
        case .bottom: (0, 90)
        case .isometric: (35, -18)
        }
    }
}
