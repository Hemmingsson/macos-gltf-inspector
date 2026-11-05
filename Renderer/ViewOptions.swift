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
    /// Real scene index, or nil for the file's default scene.
    public var sceneIndex: Int?
    public var showsFloor: Bool
    /// Draws authored camera and punctual-light gizmos in the viewport.
    public var showsSceneGizmos: Bool
    /// False frames the authored origin too.
    public var isCentered: Bool
    /// Quick Look: frame the mesh instead of the origin when the mesh sits away from it.
    /// The app leaves this off.
    public var centerWhenFarFromOrigin: Bool
    /// glTF node index for mesh / camera / light / joint selection gizmos.
    public var gizmoSelectedNodeIndex: Int?
    /// Index into `skins` when the outliner selection is a skin row.
    public var selectedSkinIndex: Int?
    /// glTF node index whose bounding box is outlined (the primary selection).
    public var selectedNodeIndex: Int?
    /// Every selected mesh or empty node; each gets the selection box. Includes the primary.
    public var selectedNodeIndices: Set<Int>
    /// Node under the pointer: a thin muted box before it is clicked.
    public var hoveredNodeIndex: Int?
    /// Orbit pivots on the selection's centre: selecting a node eases the target onto it.
    public var orbitsAroundSelection: Bool
    /// Wheel and pinch dolly toward the point under the pointer instead of the orbit target.
    public var zoomsTowardPointer: Bool
    /// Meshes using the selected material (muted AABB each); cleared for mesh/node selection.
    public var highlightedNodeIndices: Set<Int>
    /// When set, material highlights use node-local primitive bounds for this material index.
    public var materialHighlightMaterialIndex: Int?
    /// glTF node indices hidden in this window. A hidden node hides its whole subtree, draws and
    /// punctual lights alike.
    public var hiddenNodeIndices: Set<Int>
    /// When non-empty, only draws under these nodes are drawn. Lights are not affected.
    public var soloNodeIndices: Set<Int>
    /// Draws only this node: its own draws when it has any, otherwise its whole subtree. Lights
    /// are not affected.
    public var isolatedNodeIndex: Int?
    /// Mesh selection uses a screen-space silhouette; when false, mesh nodes keep the AABB lines.
    public var useSilhouetteSelectionOutline: Bool

    public init(
        look: RenderLook = .standard,
        viewMode: RenderViewMode = .shaded,
        autoRotates: Bool = false,
        isOrthographic: Bool = false,
        fieldOfView: Double = 45,
        fileCameraNodeIndex: Int? = nil,
        materialVariantIndex: Int? = nil,
        sceneIndex: Int? = nil,
        showsFloor: Bool = false,
        showsSceneGizmos: Bool = false,
        isCentered: Bool = true,
        centerWhenFarFromOrigin: Bool = false,
        selectedNodeIndex: Int? = nil,
        selectedNodeIndices: Set<Int> = [],
        hoveredNodeIndex: Int? = nil,
        orbitsAroundSelection: Bool = false,
        zoomsTowardPointer: Bool = false,
        highlightedNodeIndices: Set<Int> = [],
        materialHighlightMaterialIndex: Int? = nil,
        gizmoSelectedNodeIndex: Int? = nil,
        selectedSkinIndex: Int? = nil,
        hiddenNodeIndices: Set<Int> = [],
        soloNodeIndices: Set<Int> = [],
        isolatedNodeIndex: Int? = nil,
        useSilhouetteSelectionOutline: Bool = true
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
        self.showsSceneGizmos = showsSceneGizmos
        self.isCentered = isCentered
        self.centerWhenFarFromOrigin = centerWhenFarFromOrigin
        self.selectedNodeIndex = selectedNodeIndex
        self.selectedNodeIndices = selectedNodeIndices
        self.hoveredNodeIndex = hoveredNodeIndex
        self.orbitsAroundSelection = orbitsAroundSelection
        self.zoomsTowardPointer = zoomsTowardPointer
        self.highlightedNodeIndices = highlightedNodeIndices
        self.materialHighlightMaterialIndex = materialHighlightMaterialIndex
        self.gizmoSelectedNodeIndex = gizmoSelectedNodeIndex
        self.selectedSkinIndex = selectedSkinIndex
        self.hiddenNodeIndices = hiddenNodeIndices
        self.soloNodeIndices = soloNodeIndices
        self.isolatedNodeIndex = isolatedNodeIndex
        self.useSilhouetteSelectionOutline = useSilhouetteSelectionOutline
    }

    /// The look Settings stored in the App Group. Quick Look and the Finder thumbnail have no
    /// window state of their own, so both start here and light a file the same way.
    public static func stored(
        showsFloor: Bool = false,
        autoRotates: Bool = false,
        isCentered: Bool = true,
        centerWhenFarFromOrigin: Bool = false,
        defaults: UserDefaults = AppGroupSettings.defaults
    ) -> Self {
        Self(look: AppGroupSettings.look(defaults: defaults), autoRotates: autoRotates, showsFloor: showsFloor,
             isCentered: isCentered, centerWhenFarFromOrigin: centerWhenFarFromOrigin)
    }
}

/// Canned orbit angles. File cameras are separate.
public enum CameraPreset: String, Sendable, Hashable, CaseIterable, Identifiable {
    case front, back, left, right, top, bottom, isometric

    public var id: Self { self }

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

    public var title: String { rawValue.capitalized }

    public var systemImage: String {
        switch self {
        case .front: "arrow.up.to.line"
        case .back: "arrow.down.to.line"
        case .left: "arrow.left.to.line"
        case .right: "arrow.right.to.line"
        case .top: "arrow.up.to.line.compact"
        case .bottom: "arrow.down.to.line.compact"
        case .isometric: "cube"
        }
    }
}
