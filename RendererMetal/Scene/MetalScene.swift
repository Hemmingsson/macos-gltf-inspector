import Foundation
import GLTFKit2
import Metal
import simd

/// Deliberately matches `MetalVertex` in the hand-written MSL (80-byte stride).
public struct MetalVertex {
    public var position: SIMD4<Float>
    public var normal: SIMD4<Float>
    public var tangent: SIMD4<Float>
    public var color: SIMD4<Float>
    public var uv0: SIMD2<Float>
    public var uv1: SIMD2<Float>
}

public enum MetalTextureSlot: Int, CaseIterable, Sendable {
    case baseColor, metallicRoughness, normal, occlusion, emissive
    case specular, specularColor, clearcoat, clearcoatRoughness, clearcoatNormal
    case sheenColor, sheenRoughness, iridescence, iridescenceThickness, anisotropy
    case transmission, thickness, diffuseTransmission, diffuseTransmissionColor
    case specularGlossiness
    public var isSRGB: Bool {
        switch self {
        case .baseColor, .emissive, .specularColor, .sheenColor, .diffuseTransmissionColor: true
        default: false
        }
    }
}

public struct MetalTextureBinding {
    public let texture: any MTLTexture
    public let sampler: any MTLSamplerState
    public let texCoord: Int
    public let transform: simd_float3x3
    public let scale: Float
}

public struct MetalMaterial {
    public var baseColor = SIMD4<Float>(repeating: 1)
    public var metallic: Float = 1
    public var roughness: Float = 1
    public var emissive = SIMD3<Float>(repeating: 0)
    /// 0 opaque, 1 mask, 2 blend.
    public var alphaMode: Int = 0
    public var alphaCutoff: Float = 0.5
    public var doubleSided = false
    public var unlit = false
    public var ior: Float = 1.5
    public var specular: Float = 1
    public var specularColor = SIMD3<Float>(repeating: 1)
    public var clearcoat: Float = 0
    public var clearcoatRoughness: Float = 0
    public var sheenColor = SIMD3<Float>(repeating: 0)
    public var sheenRoughness: Float = 0
    public var iridescence: Float = 0
    public var iridescenceIOR: Float = 1.3
    public var iridescenceThicknessMin: Float = 100
    public var iridescenceThicknessMax: Float = 400
    public var anisotropy: Float = 0
    public var anisotropyRotation: Float = 0
    /// `KHR_materials_transmission` is present. Khronos groups draws by the extension, not its factor.
    public var hasTransmission = false
    public var transmission: Float = 0
    public var thickness: Float = 0
    public var attenuationDistance = Float.infinity
    public var attenuationColor = SIMD3<Float>(repeating: 1)
    public var dispersion: Float = 0
    public var diffuseTransmission: Float = 0
    public var diffuseTransmissionColor = SIMD3<Float>(repeating: 1)
    public var isSpecularGlossiness = false
    public var glossiness: Float = 1
    /// What the Khronos debug channels test with `#ifdef` (`HAS_TEXCOORD_0_VEC2`,
    /// `MATERIAL_CLEARCOAT`, `MATERIAL_SPECULAR`); absent data shows the checkerboard.
    public var hasTexCoord0 = false
    public var hasClearcoat = false
    public var hasSpecular = false
    public var textures: [MetalTextureSlot: MetalTextureBinding] = [:]
}

public struct MetalDraw {
    public let vertexBuffer: any MTLBuffer
    public let indexBuffer: any MTLBuffer
    public let indexCount: Int
    public let primitiveType: MTLPrimitiveType
    public let worldTransform: simd_float4x4
    public let material: MetalMaterial
    public let nodeIndex: Int
    public let negativeScale: Bool
    /// Khronos `Primitive.computeCentroid`: mean of the authored POSITIONs over the authored indices
    /// (before morph, skin and topology conversion), accumulated in Float32. Used for depth sorting.
    public var centroid = SIMD3<Float>(repeating: 0)
    /// Khronos opaque instancing key (`${mesh}_${winding}_${primitiveIndex}`, made unique for skins,
    /// morph targets, GPU instancing and attribute-limit fallbacks). Equal keys draw consecutively.
    public var opaqueGroup = ""
}

public struct MetalPunctualLight {
    /// 0 directional, 1 point, 2 spot.
    public let type: Int
    public let position: SIMD3<Float>
    public let direction: SIMD3<Float>
    public let color: SIMD3<Float>
    public let intensity: Float
    public let range: Float
    public let innerConeCos: Float
    public let outerConeCos: Float
}

/// CPU and Metal objects are immutable after the detached load completes.
public final class MetalScene: @unchecked Sendable {
    public let draws: [MetalDraw]
    public let boundsMin: SIMD3<Float>
    public let boundsMax: SIMD3<Float>
    public let lights: [MetalPunctualLight]
    public let triangleCount: Int
    public let nodeCount: Int
    public let materialVariantNames: [String]
    let asset: GLTFAsset

    init(draws: [MetalDraw], boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>, lights: [MetalPunctualLight], asset: GLTFAsset) {
        self.draws = draws
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.lights = lights
        self.asset = asset
        triangleCount = draws.filter { $0.primitiveType == .triangle }.reduce(0) { $0 + $1.indexCount / 3 }
        nodeCount = asset.nodes.count
        materialVariantNames = asset.materialVariants?.map { $0.name ?? "Variant" } ?? []
    }
}

public enum MetalSceneError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let text): text }
    }
}

/// Measurements the page takes from the glTF JSON rather than from drawn vertices: Khronos
/// `getSceneExtents`, viewer.html `subtreeAABB` and `gatherStatistics`. Accessor `min`/`max`
/// corners, transformed by the node's world matrix (instancing and skinning ignored, as there).
extension MetalScene {
    /// The scene the page draws for a look scene index (0 keeps the file's default scene).
    public func gltfSceneIndex(for lookIndex: Int) -> Int? {
        if lookIndex != 0 { return asset.scenes.indices.contains(lookIndex) ? lookIndex : nil }
        if let scene = asset.defaultScene, let index = asset.scenes.firstIndex(where: { $0 === scene }) { return index }
        return asset.scenes.isEmpty ? nil : 0
    }

    private func worldMatrix(_ node: GLTFNode) -> simd_float4x4 {
        (node.parent.map(worldMatrix) ?? matrix_identity_float4x4) * node.matrix
    }

    /// Expands `box` by the eight transformed corners of each POSITION accessor's min/max. With
    /// `sphere`, each primitive contributes the cube around its box's bounding sphere instead, as
    /// Khronos `getExtentsFromAccessor` does for the camera.
    private func expand(_ box: inout (min: SIMD3<Double>, max: SIMD3<Double>), node: GLTFNode, sphere: Bool = false) {
        guard let mesh = node.mesh else { return }
        let world = worldMatrix(node)
        for primitive in mesh.primitives {
            guard let accessor = primitive.attribute(forName: "POSITION")?.accessor,
                  accessor.minValues.count >= 3, accessor.maxValues.count >= 3 else { continue }
            func value(_ number: NSNumber) -> Float {
                let raw = number.floatValue
                guard accessor.isNormalized else { return raw }
                switch accessor.componentType {
                case .byte: return Swift.max(raw / 127, -1)
                case .unsignedByte: return raw / 255
                case .short: return Swift.max(raw / 32767, -1)
                case .unsignedShort: return raw / 65535
                default: return raw
                }
            }
            let lo = SIMD3(value(accessor.minValues[0]), value(accessor.minValues[1]), value(accessor.minValues[2]))
            let hi = SIMD3(value(accessor.maxValues[0]), value(accessor.maxValues[1]), value(accessor.maxValues[2]))
            var primitive = Self.emptyBox
            for i in 0..<8 {
                let corner = SIMD4<Float>(i & 4 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 1 == 0 ? lo.z : hi.z, 1)
                let p = world * corner
                let point = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))
                primitive.min = simd_min(primitive.min, point)
                primitive.max = simd_max(primitive.max, point)
            }
            if sphere {
                let center = (primitive.max + primitive.min) * 0.5
                let radius = simd_length(primitive.max - center)
                primitive = (center - radius, center + radius)
            }
            box.min = simd_min(box.min, primitive.min)
            box.max = simd_max(box.max, primitive.max)
        }
    }

    private static var emptyBox: (min: SIMD3<Double>, max: SIMD3<Double>) {
        (SIMD3(repeating: .infinity), SIMD3(repeating: -.infinity))
    }

    /// Khronos `getSceneExtents` (per-primitive bounding spheres): ±infinity when the scene has no measurable mesh, as on the page.
    public func pageExtents(sceneIndex: Int) -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        var box = Self.emptyBox
        guard asset.scenes.indices.contains(sceneIndex) else { return box }
        var stack = asset.scenes[sceneIndex].nodes
        while let node = stack.popLast() {
            stack.append(contentsOf: node.childNodes)
            expand(&box, node: node, sphere: true)
        }
        return box
    }

    /// viewer.html `subtreeAABB`: the node's subtree, or its world origin when it has no mesh.
    public func bounds(ofNode index: Int) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard asset.nodes.indices.contains(index) else { return nil }
        var box = Self.emptyBox
        var stack = [asset.nodes[index]]
        while let node = stack.popLast() {
            stack.append(contentsOf: node.childNodes)
            expand(&box, node: node)
        }
        if !box.min.x.isFinite {
            let origin = worldMatrix(asset.nodes[index]).columns.3
            let point = SIMD3(origin.x, origin.y, origin.z)
            return (point, point)
        }
        return (SIMD3<Float>(box.min), SIMD3<Float>(box.max))
    }

    /// Khronos `gatherStatistics`: meshed nodes and faces of the visible scene tree, from accessor
    /// counts (instancing ignored).
    public func pageStatistics(sceneIndex: Int) -> (meshes: Int, faces: Int) {
        guard asset.scenes.indices.contains(sceneIndex) else { return (0, 0) }
        var meshes = 0, faces = 0
        func visit(_ node: GLTFNode, visible: Bool) {
            let authored = (node.extensions["KHR_node_visibility"] as? [String: Any])?["visible"] as? Bool ?? true
            let shown = visible && authored
            if shown, let mesh = node.mesh {
                meshes += 1
                for primitive in mesh.primitives {
                    let count = primitive.indices?.count ?? primitive.attribute(forName: "POSITION")?.accessor.count ?? 0
                    guard count > 0 else { continue }
                    switch primitive.primitiveType {
                    case .points, .lineLoop: faces += count
                    case .lines: faces += count / 2
                    case .lineStrip: faces += count - 1
                    case .triangles: faces += count / 3
                    case .triangleStrip, .triangleFan: faces += count - 2
                    default: break
                    }
                }
            }
            for child in node.childNodes { visit(child, visible: shown) }
        }
        for node in asset.scenes[sceneIndex].nodes { visit(node, visible: true) }
        return (meshes, faces)
    }
}

extension MetalScene {
    /// `viewportAspect` is the aspect Khronos letterboxes the canvas to: an authored perspective
    /// `aspectRatio`, or `xmag / ymag`; nil fills the canvas. `view` is the camera's view matrix,
    /// used to depth-sort drawables the way the page sorts them.
    func fileCamera(at index: Int, aspect: Float) -> (viewProjection: simd_float4x4, view: simd_float4x4, eye: SIMD3<Float>, viewportAspect: Float?)? {
        guard asset.nodes.indices.contains(index), let camera = asset.nodes[index].camera else { return nil }
        func world(_ node: GLTFNode) -> simd_float4x4 {
            (node.parent.map(world) ?? matrix_identity_float4x4) * node.matrix
        }
        let transform = world(asset.nodes[index])
        let near = camera.zNear, far = camera.zFar
        let projection: simd_float4x4
        var viewportAspect: Float?
        if let p = camera.perspective {
            if p.aspectRatio > 0 { viewportAspect = p.aspectRatio }
            let f = 1 / tan(p.yFOV / 2)
            let ratio = p.aspectRatio > 0 ? p.aspectRatio : aspect
            projection = simd_float4x4(columns: (
                SIMD4(f / ratio, 0, 0, 0), SIMD4(0, f, 0, 0),
                SIMD4(0, 0, far.isInfinite ? -1 : (far + near) / (near - far), -1),
                SIMD4(0, 0, far.isInfinite ? -2 * near : 2 * far * near / (near - far), 0)))
        } else if let p = camera.orthographic {
            viewportAspect = p.xMag / p.yMag
            projection = simd_float4x4(columns: (
                SIMD4(1 / p.xMag, 0, 0, 0), SIMD4(0, 1 / p.yMag, 0, 0),
                SIMD4(0, 0, 2 / (near - far), 0), SIMD4(0, 0, (near + far) / (near - far), 1)))
        } else { return nil }
        return (projection * transform.inverse, transform.inverse, SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z), viewportAspect)
    }
}
