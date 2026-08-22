import Foundation
import simd

/// Host outliner + file-camera graph produced during convert.
/// Not a full glTF mirror — mesh *payloads* live on the RealityKit entity / PreviewStats.
/// Node kind/TRS/indices, lights, and materials (map presence) are stamped here at convert
/// so the sidebar can stay honest without re-parse.
struct GLTFSessionDocument: Sendable, Equatable {
    var defaultSceneIndex: Int = 0
    var scenes: [Scene] = []
    var nodes: [Node] = []
    var cameras: [Camera] = []
    var lights: [Light] = []
    var materials: [Material] = []
    var skins: [Skin] = []
    var morphs: [Morph] = []
    var animations: [Animation] = []

    struct Scene: Sendable, Equatable {
        var name: String
        var rootNodeIndices: [Int]
    }

    /// Flat glTF node with child indices — small tree, no nested copies.
    struct Node: Sendable, Equatable {
        enum Kind: String, Sendable, Equatable {
            case empty
            case mesh
            case camera
            case light
            case skin
        }

        var index: Int
        var name: String
        var children: [Int]
        var kind: Kind = .empty
        var translation: SIMD3<Float> = .zero
        var rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        var scale: SIMD3<Float> = .one
        var meshIndex: Int?
        var cameraIndex: Int?
        var lightIndex: Int?
        var skinIndex: Int?
        /// File material indices bound to this node's mesh primitives (order preserved, unique).
        var materialIndices: [Int] = []

        /// Primary attachment wins: mesh > camera > light > skin; all nil → empty.
        static func inferredKind(
            meshIndex: Int?,
            cameraIndex: Int?,
            lightIndex: Int?,
            skinIndex: Int?
        ) -> Kind {
            if meshIndex != nil { return .mesh }
            if cameraIndex != nil { return .camera }
            if lightIndex != nil { return .light }
            if skinIndex != nil { return .skin }
            return .empty
        }
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

    /// `KHR_lights_punctual` entry. `type` is `directional` / `point` / `spot`.
    /// `range` nil = infinite (glTF default). Cone angles only for spots (radians).
    struct Light: Sendable, Equatable {
        var name: String
        var type: String
        var color: SIMD3<Float>
        var intensity: Float
        var range: Float?
        var innerCone: Float?
        var outerCone: Float?
    }

    /// File material + texture-map presence. `maps` is canonical for sidebar chips;
    /// `PreviewDebugMode` aggregates the same flags (JSON twin) with mesh/factor signals.
    struct Material: Sendable, Equatable {
        enum Workflow: String, Sendable, Equatable {
            case metallicRoughness
            case specularGlossiness
            case unlit
        }

        enum AlphaMode: String, Sendable, Equatable {
            case opaque
            case mask
            case blend
        }

        var name: String
        var maps: MaterialMapPresence
        var workflow: Workflow = .metallicRoughness
        var alphaMode: AlphaMode = .opaque
        var isDoubleSided: Bool = false
        var metallicFactor: Float?
        var roughnessFactor: Float?
        var alphaCutoff: Float?
    }

    /// Skin joint list stamped at convert (P16). `jointParentIndices` indexes this
    /// skin’s joint array (`nil` = root). Overlay looks up entities via `jointNodeIndices`.
    struct Skin: Sendable, Equatable {
        var name: String
        var jointNames: [String]
        var jointNodeIndices: [Int]
        var jointParentIndices: [Int?]
    }

    /// Morph targets for one mesh (P16). Names match RealityKit blend-shape offsets.
    struct Morph: Sendable, Equatable {
        var meshIndex: Int
        var meshName: String
        var targetNames: [String]
    }

    struct Animation: Sendable, Equatable {
        var name: String
        var duration: Double
    }
}
