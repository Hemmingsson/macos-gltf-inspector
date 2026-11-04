import Foundation
import simd

/// What a glTF file contains, as authored, read from its JSON (`GLTFDocumentJSON`): the outliner
/// and inspector show this. No mesh payloads: the renderer loads the file on its own.
public struct GLTFDocument: Sendable, Equatable {
    public var defaultSceneIndex: Int = 0
    /// Bounds of the default scene; nil when no mesh node has usable `POSITION` bounds.
    public var bounds: ModelBounds?
    /// `KHR_materials_variants` names in file order; empty when the extension is absent.
    public var materialVariantNames: [String] = []
    /// View modes the file has data for (`ViewModeAvailability`).
    public var viewModes: [RenderViewMode] = [.shaded]
    public var scenes: [Scene] = []
    public var nodes: [Node] = []
    public var cameras: [Camera] = []
    public var lights: [Light] = []
    public var materials: [Material] = []
    public var skins: [Skin] = []
    public var morphs: [Morph] = []
    public var animations: [Animation] = []
    /// Material index of every primitive, per mesh (`meshPrimitiveMaterials[mesh][primitive]`).
    /// Nil for a primitive with no material. Lets a validator pointer such as
    /// `/meshes/0/primitives/1` reach the material that primitive uses.
    public var meshPrimitiveMaterials: [[Int?]] = []

    public init() {}

    public struct Scene: Sendable, Equatable {
        public var name: String
        public var rootNodeIndices: [Int]
    }

    /// Flat glTF node with child indices — small tree, no nested copies.
    public struct Node: Sendable, Equatable {
        public enum Kind: String, Sendable, Equatable {
            case empty
            case mesh
            case camera
            case light
            case skin
        }

        public var index: Int
        public var name: String
        public var children: [Int]
        public var kind: Kind = .empty
        public var translation: SIMD3<Float> = .zero
        public var rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        public var scale: SIMD3<Float> = .one
        public var meshIndex: Int?
        public var cameraIndex: Int?
        public var lightIndex: Int?
        public var skinIndex: Int?
        /// File material indices bound to this node's mesh primitives (order preserved, unique).
        public var materialIndices: [Int] = []
        /// Derived from the referenced mesh's primitives (mesh nodes only).
        public var triangleCount: Int = 0
        public var vertexCount: Int = 0
        public var uvSetCount: Int = 0
        public var hasTangents: Bool = false
        public var hasVertexColors: Bool = false

        /// Primary attachment wins: mesh > camera > light > skin; all nil → empty.
        public static func inferredKind(
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

    public struct Camera: Sendable, Equatable {
        public var name: String
        public var type: String
        public var yfov: Float?
        public var znear: Float
        public var zfar: Float?
        public var xmag: Float?
        public var ymag: Float?
    }

    /// `KHR_lights_punctual` entry. `type` is `directional` / `point` / `spot`.
    /// `range` nil = infinite (glTF default). Cone angles only for spots (radians).
    public struct Light: Sendable, Equatable {
        public var name: String
        public var type: String
        public var color: SIMD3<Float>
        public var intensity: Float
        public var range: Float?
        public var innerCone: Float?
        public var outerCone: Float?
    }

    /// Authored texture slot on a material. Pixel size / thumb stamped from the file bytes.
    public struct TextureSlot: Sendable, Equatable {
        /// In inspector order.
        public enum Kind: String, Sendable, Hashable, CaseIterable {
            case baseColor
            case normal
            case metallicRoughness
            case occlusion
            case emissive
            case clearcoat
            case clearcoatRoughness
            case clearcoatNormal
            case specular
        }

        public var kind: Kind
        public var texCoord: Int = 0
        /// glTF `textures` index this slot binds. Nil when the binding carries none.
        public var textureIndex: Int?
        /// glTF `images` index behind that texture, once resolved against the file.
        public var imageIndex: Int?
        public var width: Int?
        public var height: Int?
        public var thumbnailPNG: Data?
    }

    public struct Material: Sendable, Equatable {
        public enum Workflow: String, Sendable, Equatable {
            case metallicRoughness
            case specularGlossiness
            case unlit
        }

        public enum AlphaMode: String, Sendable, Equatable {
            case opaque
            case mask
            case blend
        }

        public var name: String
        public var workflow: Workflow = .metallicRoughness
        public var alphaMode: AlphaMode = .opaque
        public var isDoubleSided: Bool = false
        public var metallicFactor: Float?
        public var roughnessFactor: Float?
        public var alphaCutoff: Float?
        public var baseColorFactor: SIMD4<Float>?
        public var emissiveFactor: SIMD3<Float>?
        /// `KHR_materials_emissive_strength`. Nil when the extension is absent (spec default 1).
        public var emissiveStrength: Float?
        public var normalScale: Float?
        public var occlusionStrength: Float?
        /// Bound maps in inspector order; thumbs stamped from the file bytes.
        public var textures: [TextureSlot] = []
    }

    /// Skin joint names from the JSON.
    public struct Skin: Sendable, Equatable {
        public var name: String
        public var jointNames: [String]
    }

    /// Morph targets for one mesh (`extras.targetNames`, else by index).
    public struct Morph: Sendable, Equatable {
        public var meshIndex: Int
        public var meshName: String
        public var targetNames: [String]
    }

    /// One per JSON animation, so indices match validator pointers.
    public struct Animation: Sendable, Equatable {
        public var name: String
        /// Seconds; 0 for a clip with fewer than two keyframes or no span.
        public var duration: Double
    }
}

extension GLTFDocument {
    /// Reads a `.gltf` or a GLB's JSON chunk (plus texture headers for the inspector) off the main
    /// thread. Throws for a file that is not glTF.
    public static func load(from url: URL) async throws -> GLTFDocument {
        try await Task.detached(priority: .userInitiated) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return GLTFDocumentJSON.makeDocument(json: try GLBBox.peekDocumentJSON(from: url), fileURL: url)
        }.value
    }
}
