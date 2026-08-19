import Foundation
import simd

struct GLTFSessionDocument: Sendable, Equatable {
    var defaultSceneIndex: Int = 0
    var scenes: [Scene] = []
    var nodes: [Node] = []
    var meshes: [Mesh] = []
    var materials: [Material] = []
    var lights: [Light] = []
    var cameras: [Camera] = []
    var animations: [Animation] = []
    var variants: [Variant] = []

    struct Scene: Sendable, Equatable {
        var name: String
        var rootNodeIndices: [Int]
    }

    struct Node: Sendable, Equatable {
        var index: Int
        var name: String
        var children: [Int]
        var meshIndex: Int?
        var cameraIndex: Int?
        var lightIndex: Int?
        var translation: SIMD3<Float>
        /// glTF quaternion xyzw (same as simd_quatf.vector); identity (0, 0, 0, 1).
        var rotation: SIMD4<Float>
        var scale: SIMD3<Float>
    }

    struct Mesh: Sendable, Equatable {
        var name: String
        var primitiveCount: Int
        var triangleCount: Int
        var vertexCount: Int
        var materialIndices: [Int]
    }

    struct Material: Sendable, Equatable {
        var name: String
        var baseColorFactor: SIMD4<Float>
        var metallicFactor: Float
        var roughnessFactor: Float
        var emissiveFactor: SIMD3<Float>
        var alphaMode: String
        var hasBaseColorTexture: Bool
        var hasMetallicRoughnessTexture: Bool
        var hasNormalTexture: Bool
        var hasOcclusionTexture: Bool
        var hasEmissiveTexture: Bool
    }

    struct Light: Sendable, Equatable {
        var name: String
        var type: String
        var color: SIMD3<Float>
        var intensity: Float
        var range: Float?
        var innerCone: Float?
        var outerCone: Float?
    }

    struct Camera: Sendable, Equatable {
        var name: String
        var type: String
        var yfov: Float?
        var znear: Float
        var zfar: Float?
        var xmag: Float?
        var ymag: Float?
    }

    struct Animation: Sendable, Equatable {
        var name: String
        var duration: Double
    }

    struct Variant: Sendable, Equatable {
        var name: String
        /// primitiveKey `"meshIndex:primitiveIndex"` → material index
        var mapping: [String: Int]
    }
}
