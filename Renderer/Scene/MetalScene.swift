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
    /// `HAS_NORMAL_VEC3`, `HAS_TANGENT_VEC4`, `MATERIAL_CLEARCOAT`, `MATERIAL_SPECULAR`);
    /// absent data shows the checkerboard, and a missing tangent uses screen-space derivatives.
    public var hasTexCoord0 = false
    public var hasNormal = false
    public var hasTangent = false
    public var hasClearcoat = false
    public var hasSpecular = false
    public var textures: [MetalTextureSlot: MetalTextureBinding] = [:]
}

public struct MetalDraw {
    public let vertexBuffer: any MTLBuffer
    public let indexBuffer: any MTLBuffer
    public let indexCount: Int
    public let primitiveType: MTLPrimitiveType
    /// Rest model, including the instance matrix. A posed frame replaces this per draw.
    public let worldTransform: simd_float4x4
    /// `EXT_mesh_gpu_instancing` transform for this draw, or identity.
    public let instanceMatrix: simd_float4x4
    public let material: MetalMaterial
    public let nodeIndex: Int
    public let negativeScale: Bool
    /// Khronos `Primitive.computeCentroid`: mean of the authored POSITIONs over the authored indices
    /// (before morph, skin and topology conversion), accumulated in Float32. Used for depth sorting.
    public var centroid = SIMD3<Float>(repeating: 0)
    /// Khronos opaque instancing key (`${mesh}_${winding}_${primitiveIndex}`, made unique for skins,
    /// morph targets, GPU instancing and attribute-limit fallbacks). Equal keys draw consecutively.
    public var opaqueGroup = ""
    /// Index into `asset.meshes`, or -1 when the node has no mesh.
    let meshIndex: Int
    /// Authored `node.weights`, otherwise `mesh.weights`, otherwise zeros. One entry per target.
    let restWeights: [Float]
    /// Packed `float4` deltas, `[presentSlot][target][emittedVertex]`. Nil when nothing is morphed.
    let morphBuffer: (any MTLBuffer)?
    let morphTargetCount: Int
    /// Emitted vertex count. The shader indexes this buffer with `vertex_id`.
    let morphVertexCount: Int
    /// Bits in `MorphSlot` order: position, normal, tangent, texcoord0, texcoord1, color0.
    let morphMask: UInt32
    /// `{ushort4, ushort4, float4, float4}` per emitted vertex. Nil when the primitive is not skinned.
    let skinBuffer: (any MTLBuffer)?
    /// Index into `MetalScene.skins`.
    let skinIndex: Int?
    /// The primitive has JOINTS_1 and WEIGHTS_1. The shader specialization skips that set otherwise.
    let hasJoints1: Bool

    init(vertexBuffer: any MTLBuffer, indexBuffer: any MTLBuffer, indexCount: Int,
         primitiveType: MTLPrimitiveType, worldTransform: simd_float4x4, instanceMatrix: simd_float4x4,
         material: MetalMaterial, nodeIndex: Int, negativeScale: Bool, centroid: SIMD3<Float> = .zero,
         opaqueGroup: String = "", meshIndex: Int = -1, restWeights: [Float] = [],
         morphBuffer: (any MTLBuffer)? = nil, morphTargetCount: Int = 0, morphVertexCount: Int = 0,
         morphMask: UInt32 = 0, skinBuffer: (any MTLBuffer)? = nil, skinIndex: Int? = nil,
         hasJoints1: Bool = false) {
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.primitiveType = primitiveType
        self.worldTransform = worldTransform
        self.instanceMatrix = instanceMatrix
        self.material = material
        self.nodeIndex = nodeIndex
        self.negativeScale = negativeScale
        self.centroid = centroid
        self.opaqueGroup = opaqueGroup
        self.meshIndex = meshIndex
        self.restWeights = restWeights
        self.morphBuffer = morphBuffer
        self.morphTargetCount = morphTargetCount
        self.morphVertexCount = morphVertexCount
        self.morphMask = morphMask
        self.skinBuffer = skinBuffer
        self.skinIndex = skinIndex
        self.hasJoints1 = hasJoints1
    }
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
    /// glTF node index in `asset.nodes`, or -1 if unknown.
    public let nodeIndex: Int
}

/// CPU and Metal objects are immutable after the detached load completes.
public final class MetalScene: @unchecked Sendable {
    public let draws: [MetalDraw]
    public let boundsMin: SIMD3<Float>
    public let boundsMax: SIMD3<Float>
    public let lights: [MetalPunctualLight]
    /// Parent node index for each index in `asset.nodes`, or -1 for a root.
    public let nodeParents: [Int]
    /// Load-time TRS and world matrix for each node, parallel to `asset.nodes`.
    let nodeRests: [MetalNodeRest]
    /// Skins parallel to `asset.skins`. Draws point at these with `skinIndex`.
    let skins: [MetalSkin]
    /// Children of each node, in index order. Used to push a posed parent into its subtree.
    let nodeChildren: [[Int]]
    /// glTF node indices reachable from the loaded scene's roots.
    let inSceneNodes: Set<Int>
    /// Subset of `inSceneNodes` that are not under an authored-hidden ancestor (`KHR_node_visibility`).
    let visibleNodes: Set<Int>
    let asset: GLTFAsset

    init(draws: [MetalDraw], boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>, lights: [MetalPunctualLight],
         asset: GLTFAsset, nodeRests: [MetalNodeRest], skins: [MetalSkin],
         inSceneNodes: Set<Int>, visibleNodes: Set<Int>) {
        self.draws = draws
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.lights = lights
        self.asset = asset
        self.nodeRests = nodeRests
        self.skins = skins
        self.inSceneNodes = inSceneNodes
        self.visibleNodes = visibleNodes
        let indices = Dictionary(asset.nodes.enumerated().map { (ObjectIdentifier($1), $0) }, uniquingKeysWith: { first, _ in first })
        nodeParents = asset.nodes.map { node in node.parent.flatMap { indices[ObjectIdentifier($0)] } ?? -1 }
        var children = Array(repeating: [Int](), count: nodeParents.count)
        for (index, parent) in nodeParents.enumerated() where children.indices.contains(parent) {
            children[parent].append(index)
        }
        nodeChildren = children
    }

    /// The node itself, then its parent, grandparent and so on up to a root. Empty for an index
    /// outside `asset.nodes`.
    public func ancestors(ofNode index: Int) -> [Int] {
        var chain: [Int] = []
        var current = index
        while nodeParents.indices.contains(current) {
            chain.append(current)
            current = nodeParents[current]
        }
        return chain
    }

    /// Active scene membership, authored visibility, and this window's hide / solo filters.
    public func isEffectivelyVisible(node index: Int, hidden: Set<Int>, solo: Set<Int>) -> Bool {
        guard inSceneNodes.contains(index), visibleNodes.contains(index) else { return false }
        let chain = ancestors(ofNode: index)
        if chain.contains(where: { hidden.contains($0) }) { return false }
        if !solo.isEmpty && !chain.contains(where: { solo.contains($0) }) { return false }
        return true
    }
}

public enum MetalSceneError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let text): text }
    }
}

/// Measurements the Khronos viewer takes from the glTF JSON rather than from drawn vertices
/// (`getSceneExtents`, `subtreeAABB`): accessor `min`/`max` corners, transformed by the node's
/// world matrix, instancing and skinning ignored.
extension MetalScene {
    /// The scene drawn for `ViewOptions.sceneIndex` (nil keeps the file's default scene).
    func gltfSceneIndex(for sceneIndex: Int?) -> Int? {
        if let sceneIndex { return asset.scenes.indices.contains(sceneIndex) ? sceneIndex : nil }
        if let scene = asset.defaultScene, let index = asset.scenes.firstIndex(where: { $0 === scene }) { return index }
        return asset.scenes.isEmpty ? nil : 0
    }

    func worldMatrix(_ node: GLTFNode) -> simd_float4x4 {
        (node.parent.map(worldMatrix) ?? matrix_identity_float4x4) * node.matrix
    }

    public func worldMatrix(ofNode index: Int) -> simd_float4x4? {
        guard asset.nodes.indices.contains(index) else { return nil }
        return worldMatrix(asset.nodes[index])
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

    /// Khronos `getSceneExtents` (per-primitive bounding spheres): ±infinity when the scene has
    /// no measurable mesh.
    func accessorExtents(sceneIndex: Int) -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        var box = Self.emptyBox
        guard asset.scenes.indices.contains(sceneIndex) else { return box }
        var stack = asset.scenes[sceneIndex].nodes
        while let node = stack.popLast() {
            stack.append(contentsOf: node.childNodes)
            expand(&box, node: node, sphere: true)
        }
        return box
    }

    /// Axis-aligned mesh bounds in the node's local space (POSITION accessor min/max).
    func localMeshSize(ofNode index: Int) -> SIMD3<Float>? {
        guard asset.nodes.indices.contains(index), let mesh = asset.nodes[index].mesh else { return nil }
        var lo = SIMD3<Float>(repeating: .infinity)
        var hi = SIMD3<Float>(repeating: -.infinity)
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
            let cornerLo = SIMD3(value(accessor.minValues[0]), value(accessor.minValues[1]), value(accessor.minValues[2]))
            let cornerHi = SIMD3(value(accessor.maxValues[0]), value(accessor.maxValues[1]), value(accessor.maxValues[2]))
            lo = min(lo, cornerLo)
            hi = max(hi, cornerHi)
        }
        guard lo.x.isFinite else { return nil }
        return hi - lo
    }

    /// Absolute scale extracted from the node's world matrix column lengths.
    func worldScale(ofNode index: Int) -> SIMD3<Float>? {
        guard let matrix = worldMatrix(ofNode: index) else { return nil }
        return SIMD3(
            simd_length(SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)),
            simd_length(SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)),
            simd_length(SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        )
    }

    /// `subtreeAABB`: the node's subtree, or its world origin when it has no mesh.
    func bounds(ofNode index: Int) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
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
}

extension MetalScene {
    /// `viewportAspect` is the aspect Khronos letterboxes the canvas to: an authored perspective
    /// `aspectRatio`, or `xmag / ymag`; nil fills the canvas. `view` is the camera's view matrix,
    /// used to depth-sort drawables the way the viewer sorts them.
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
