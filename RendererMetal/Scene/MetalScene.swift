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

extension MetalScene {
    public func bounds(ofNode index: Int) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard asset.nodes.indices.contains(index) else { return nil }
        var included: Set<Int> = []
        func collect(_ node: GLTFNode) {
            if let i = asset.nodes.firstIndex(where: { $0 === node }) { included.insert(i) }
            for child in node.childNodes { collect(child) }
        }
        collect(asset.nodes[index])
        var minimum = SIMD3<Float>(repeating: .infinity), maximum = SIMD3<Float>(repeating: -.infinity)
        for draw in draws where included.contains(draw.nodeIndex) {
            let count = draw.vertexBuffer.length / MemoryLayout<MetalVertex>.stride
            let vertices = draw.vertexBuffer.contents().bindMemory(to: MetalVertex.self, capacity: count)
            for i in 0..<count {
                let point = draw.worldTransform * vertices[i].position
                let p = SIMD3(point.x, point.y, point.z) / point.w
                minimum = simd_min(minimum, p); maximum = simd_max(maximum, p)
            }
        }
        return minimum.x.isFinite ? (minimum, maximum) : nil
    }
}

extension MetalScene {
    func fileCamera(at index: Int, aspect: Float) -> (viewProjection: simd_float4x4, view: simd_float4x4, eye: SIMD3<Float>)? {
        guard asset.nodes.indices.contains(index), let camera = asset.nodes[index].camera else { return nil }
        func world(_ node: GLTFNode) -> simd_float4x4 {
            (node.parent.map(world) ?? matrix_identity_float4x4) * node.matrix
        }
        let transform = world(asset.nodes[index])
        let near = camera.zNear, far = camera.zFar
        let projection: simd_float4x4
        if let p = camera.perspective {
            let f = 1 / tan(p.yFOV / 2)
            let ratio = p.aspectRatio > 0 ? p.aspectRatio : aspect
            projection = simd_float4x4(columns: (
                SIMD4(f / ratio, 0, 0, 0), SIMD4(0, f, 0, 0),
                SIMD4(0, 0, far.isInfinite ? -1 : (far + near) / (near - far), -1),
                SIMD4(0, 0, far.isInfinite ? -2 * near : 2 * far * near / (near - far), 0)))
        } else if let p = camera.orthographic {
            projection = simd_float4x4(columns: (
                SIMD4(1 / p.xMag, 0, 0, 0), SIMD4(0, 1 / p.yMag, 0, 0),
                SIMD4(0, 0, 2 / (near - far), 0), SIMD4(0, 0, (near + far) / (near - far), 1)))
        } else { return nil }
        return (projection * transform.inverse, transform.inverse, SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z))
    }
}
