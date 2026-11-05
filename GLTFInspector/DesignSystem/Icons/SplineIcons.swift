import GLTFCore
import SwiftUI

/// Catalog names for Spline artwork in `SplineSpike.xcassets` (materials, mesh, camera, instance).
/// Lights use Blender icons via `BlenderIcons` / `GLTFDocument.assetImage(for:)`.
enum SplineIcons {
    /// Four-dot component glyph for a mesh referenced by more than one node.
    static let sharedMesh = "spline.type.component"
    static let cameraPerspective = "icon.camera.perspective"
    static let cameraOrthographic = "icon.camera.orthographic"

    static func nodeKind(_ kind: NodeKind) -> String? {
        switch kind {
        case .mesh: "spline.type.cube"
        case .camera: "spline.type.camera"
        case .material: "spline.material.preview"
        default: nil
        }
    }

    static func textureSlot(_ kind: GLTFDocument.TextureSlot.Kind) -> String {
        switch kind {
        case .baseColor: "spline.material.image"
        case .normal, .clearcoatNormal: "spline.material.normal"
        case .occlusion: "spline.material.cavity"
        case .metallicRoughness: "spline.material.matcap"
        case .emissive: "spline.material.fresnel"
        case .specular: "spline.material.reflection"
        case .clearcoat, .clearcoatRoughness: "spline.material.toon"
        }
    }

    static func viewChannel(_ channel: RenderViewMode.Channel) -> String {
        switch channel {
        case .baseColor: "spline.material.image"
        case .normals, .clearcoatNormal, .tangents: "spline.material.normal"
        case .ambientOcclusion: "spline.material.cavity"
        case .metallic, .roughness: "spline.material.matcap"
        case .emissive: "spline.material.fresnel"
        case .specular: "spline.material.reflection"
        case .clearcoat, .clearcoatRoughness: "spline.material.toon"
        case .alpha: "spline.material.checker"
        case .textureCoordinates: "spline.material.pattern"
        }
    }

    static func viewMode(_ mode: RenderViewMode) -> String? {
        switch mode {
        case .shaded: "spline.material.preview"
        case .wireframe, .wireframeOnShaded, .xray, .clay: nil
        case .channel(let channel): viewChannel(channel)
        }
    }
}
