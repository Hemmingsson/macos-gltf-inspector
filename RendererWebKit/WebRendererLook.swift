import Foundation
import GLTFCore

extension WebPreviewCanvas {
    /// Everything the page draws with, as one value: the renderer-neutral `RenderLook` plus the
    /// canvas's view state. Sent whole (`WebRendererHost.apply`); the page applies it in one call
    /// and only redoes the expensive parts (IBL, refit) when those values changed.
    ///
    /// The defaults are the page's own opening state, so `Look()` changes nothing and a still
    /// (thumbnail, pixel diff) gets no floor or overlays.
    public struct Look: Equatable, Sendable {
        public var render: RenderLook
        var viewMode: RenderViewMode
        var autoRotates: Bool
        var isOrthographic: Bool
        /// Vertical field of view in degrees.
        var fieldOfView: Double
        /// Camera authored in the file, or nil for the user camera.
        var fileCameraIndex: Int?
        /// `KHR_materials_variants` index, or nil for the file default.
        var materialVariantIndex: Int?
        /// Scene index; 0 keeps the file's default scene.
        var sceneIndex: Int
        var showsFloor: Bool
        /// False shows the authored-origin gizmo and frames so the origin is visible.
        var isCentered: Bool
        /// glTF node index highlighted on the canvas.
        var selectedNodeIndex: Int?

        public init(
            render: RenderLook = .standard,
            viewMode: RenderViewMode = .shaded,
            autoRotates: Bool = false,
            isOrthographic: Bool = false,
            fieldOfView: Double = 45,
            fileCameraIndex: Int? = nil,
            materialVariantIndex: Int? = nil,
            sceneIndex: Int = 0,
            showsFloor: Bool = false,
            isCentered: Bool = true,
            selectedNodeIndex: Int? = nil
        ) {
            self.render = render
            self.viewMode = viewMode
            self.autoRotates = autoRotates
            self.isOrthographic = isOrthographic
            self.fieldOfView = fieldOfView
            self.fileCameraIndex = fileCameraIndex
            self.materialVariantIndex = materialVariantIndex
            self.sceneIndex = sceneIndex
            self.showsFloor = showsFloor
            self.isCentered = isCentered
            self.selectedNodeIndex = selectedNodeIndex
        }

        /// The look Settings stored in the App Group, for surfaces with no window state of their
        /// own. Quick Look and the Finder thumbnail both start here, so they light a file the
        /// same way.
        public static func stored(
            showsFloor: Bool = false,
            defaults: UserDefaults = AppGroupSettings.defaults,
            directory: URL = AppGroupSettings.containerURL
        ) -> Self {
            Self(
                render: AppGroupSettings.rendererLook(defaults: defaults, directory: directory),
                showsFloor: showsFloor
            )
        }
    }
}

/// The look in the page's own terms — the one place `RenderLook` meets the Khronos renderer.
///
/// | `RenderLook` | Page (`GltfState.renderingParameters`) | Source |
/// | --- | --- | --- |
/// | `environmentYawDegrees` Y | `environmentRotation` = 90 + Y (Khronos default view at Y = 0) | measured (look probes) |
/// | `exposureEV` | `exposure` = 2^EV | measured |
/// | `environmentIntensity` E | `iblIntensity` = E | measured (1:1) |
/// | `toneMapping` | `toneMap` (raw value is the Khronos name) | by definition |
/// | `background` | page background behind a transparent canvas | by definition |
/// | `environment` | bundled `.hdr` served at `/environments/<stem>.hdr` | by definition |
/// | `usesFileLights`, `usesEnvironment` | not mapped: the page draws file lights as authored and always uses the IBL | assumed |
struct PageLook: Encodable, Equatable {
    /// Khronos default: `environmentRotation` 90 is the Sample Viewer's view, and yaw 0 means that.
    static let khronosDefaultRotation = 90.0

    /// HDR URL; nil only for instrumentation that wants no IBL at all (look probes).
    var environment: String?
    var toneMap: String
    var exposure: Double
    var environmentRotation: Double
    var iblIntensity: Double
    var background: [Double]
    var debugOutput: String
    var wireframe: Bool
    var autoRotate: Bool
    var orthographic: Bool
    var yfov: Double
    var cameraNodeIndex: Int?
    var variant: Int?
    var sceneIndex: Int
    var floor: Bool
    var centered: Bool
    var selectedNode: Int?

    init(_ look: WebPreviewCanvas.Look) {
        let render = look.render
        environment = Self.environmentURL(render.environment.rawValue)
        toneMap = render.toneMapping.rawValue
        exposure = render.exposureEV
        environmentRotation = Self.khronosDefaultRotation + render.environmentYawDegrees
        iblIntensity = render.environmentIntensity
        let color = render.background
        background = [color.red, color.green, color.blue, color.alpha]
        debugOutput = Self.debugOutput(look.viewMode)
        wireframe = look.viewMode == .wireframe
        autoRotate = look.autoRotates
        orthographic = look.isOrthographic
        yfov = look.fieldOfView
        cameraNodeIndex = look.fileCameraIndex
        variant = look.materialVariantIndex
        sceneIndex = look.sceneIndex
        floor = look.showsFloor
        centered = look.isCentered
        selectedNode = look.selectedNodeIndex
    }

    static func environmentURL(_ stem: String) -> String {
        "\(WebRendererResourceHandler.scheme):///environments/\(stem).hdr"
    }

    /// `GltfState.DebugOutput` values — matched by string in the renderer, so they must be exact.
    /// Wireframe is a page overlay, not a Khronos channel.
    static func debugOutput(_ mode: RenderViewMode) -> String {
        guard case .channel(let channel) = mode else { return "None" }
        return switch channel {
        case .baseColor: "Base Color"
        case .metallic: "Metallic"
        case .roughness: "Roughness"
        case .normals: "Normal Texture"
        case .tangents: "Geometry Tangent"
        case .textureCoordinates: "Texture Coordinates 0"
        case .ambientOcclusion: "Occlusion"
        case .emissive: "Emissive"
        case .alpha: "Alpha"
        case .specular: "Specular Strength"
        case .clearcoat: "ClearCoat Strength"
        case .clearcoatRoughness: "ClearCoat Roughness"
        case .clearcoatNormal: "ClearCoat Normal"
        }
    }
}
