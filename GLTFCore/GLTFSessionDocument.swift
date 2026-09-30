import Foundation
import simd

/// Host outliner + file-camera graph, parsed from the glTF JSON by `GLTFDocumentJSON`.
/// Not a full glTF mirror — mesh *payloads* live on the renderer's own scene / PreviewStats.
/// Describes the file as authored, so it lists nodes, materials and clips the renderer
/// rewrites or cannot show.
public struct GLTFSessionDocument: Sendable, Equatable {
    public var defaultSceneIndex: Int = 0
    public var scenes: [Scene] = []
    public var nodes: [Node] = []
    public var cameras: [Camera] = []
    public var lights: [Light] = []
    public var materials: [Material] = []
    public var skins: [Skin] = []
    public var morphs: [Morph] = []
    public var animations: [Animation] = []

    public init(
        defaultSceneIndex: Int = 0,
        scenes: [Scene] = [],
        nodes: [Node] = [],
        cameras: [Camera] = [],
        lights: [Light] = [],
        materials: [Material] = [],
        skins: [Skin] = [],
        morphs: [Morph] = [],
        animations: [Animation] = []
    ) {
        self.defaultSceneIndex = defaultSceneIndex
        self.scenes = scenes
        self.nodes = nodes
        self.cameras = cameras
        self.lights = lights
        self.materials = materials
        self.skins = skins
        self.morphs = morphs
        self.animations = animations
    }

    public struct Scene: Sendable, Equatable {
        public var name: String
        public var rootNodeIndices: [Int]

        public init(
            name: String,
            rootNodeIndices: [Int]
        ) {
            self.name = name
            self.rootNodeIndices = rootNodeIndices
        }
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
        public var hasNormals: Bool = false
        public var hasTangents: Bool = false
        public var hasVertexColors: Bool = false

        public init(
            index: Int,
            name: String,
            children: [Int],
            kind: Kind = .empty,
            translation: SIMD3<Float> = .zero,
            rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            scale: SIMD3<Float> = .one,
            meshIndex: Int? = nil,
            cameraIndex: Int? = nil,
            lightIndex: Int? = nil,
            skinIndex: Int? = nil,
            materialIndices: [Int] = [],
            triangleCount: Int = 0,
            vertexCount: Int = 0,
            uvSetCount: Int = 0,
            hasNormals: Bool = false,
            hasTangents: Bool = false,
            hasVertexColors: Bool = false
        ) {
            self.index = index
            self.name = name
            self.children = children
            self.kind = kind
            self.translation = translation
            self.rotation = rotation
            self.scale = scale
            self.meshIndex = meshIndex
            self.cameraIndex = cameraIndex
            self.lightIndex = lightIndex
            self.skinIndex = skinIndex
            self.materialIndices = materialIndices
            self.triangleCount = triangleCount
            self.vertexCount = vertexCount
            self.uvSetCount = uvSetCount
            self.hasNormals = hasNormals
            self.hasTangents = hasTangents
            self.hasVertexColors = hasVertexColors
        }

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

        public init(
            name: String,
            type: String,
            yfov: Float? = nil,
            znear: Float,
            zfar: Float? = nil,
            xmag: Float? = nil,
            ymag: Float? = nil
        ) {
            self.name = name
            self.type = type
            self.yfov = yfov
            self.znear = znear
            self.zfar = zfar
            self.xmag = xmag
            self.ymag = ymag
        }
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

        public init(
            name: String,
            type: String,
            color: SIMD3<Float>,
            intensity: Float,
            range: Float? = nil,
            innerCone: Float? = nil,
            outerCone: Float? = nil
        ) {
            self.name = name
            self.type = type
            self.color = color
            self.intensity = intensity
            self.range = range
            self.innerCone = innerCone
            self.outerCone = outerCone
        }
    }

    /// Authored texture slot on a material. Pixel size / thumb filled after convert.
    public struct TextureSlot: Sendable, Equatable {
        public enum Kind: String, Sendable, Equatable {
            case baseColor
            case normal
            case metallicRoughness
            case occlusion
            case emissive
            case specular
            case clearcoat
            case clearcoatRoughness
            case clearcoatNormal
        }

        public var kind: Kind
        public var texCoord: Int = 0
        public var width: Int?
        public var height: Int?
        public var thumbnailPNG: Data?

        public init(
            kind: Kind,
            texCoord: Int = 0,
            width: Int? = nil,
            height: Int? = nil,
            thumbnailPNG: Data? = nil
        ) {
            self.kind = kind
            self.texCoord = texCoord
            self.width = width
            self.height = height
            self.thumbnailPNG = thumbnailPNG
        }
    }

    /// File material + texture-map presence. `maps` is canonical for sidebar chips;
    /// `PreviewDebugMode` aggregates the same flags (JSON twin) with mesh/factor signals.
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
        public var maps: MaterialMapPresence
        public var workflow: Workflow = .metallicRoughness
        public var alphaMode: AlphaMode = .opaque
        public var isDoubleSided: Bool = false
        public var metallicFactor: Float?
        public var roughnessFactor: Float?
        public var alphaCutoff: Float?
        public var baseColorFactor: SIMD4<Float>?
        public var emissiveFactor: SIMD3<Float>?
        public var normalScale: Float?
        public var occlusionStrength: Float?
        /// Present map bindings; thumbs stamped after convert.
        public var textures: [TextureSlot] = []

        public init(
            name: String,
            maps: MaterialMapPresence,
            workflow: Workflow = .metallicRoughness,
            alphaMode: AlphaMode = .opaque,
            isDoubleSided: Bool = false,
            metallicFactor: Float? = nil,
            roughnessFactor: Float? = nil,
            alphaCutoff: Float? = nil,
            baseColorFactor: SIMD4<Float>? = nil,
            emissiveFactor: SIMD3<Float>? = nil,
            normalScale: Float? = nil,
            occlusionStrength: Float? = nil,
            textures: [TextureSlot] = []
        ) {
            self.name = name
            self.maps = maps
            self.workflow = workflow
            self.alphaMode = alphaMode
            self.isDoubleSided = isDoubleSided
            self.metallicFactor = metallicFactor
            self.roughnessFactor = roughnessFactor
            self.alphaCutoff = alphaCutoff
            self.baseColorFactor = baseColorFactor
            self.emissiveFactor = emissiveFactor
            self.normalScale = normalScale
            self.occlusionStrength = occlusionStrength
            self.textures = textures
        }
    }

    /// Skin joint list stamped at convert. `jointParentIndices` indexes this
    /// skin’s joint array (`nil` = root). Overlay looks up entities via `jointNodeIndices`.
    public struct Skin: Sendable, Equatable {
        public var name: String
        public var jointNames: [String]
        public var jointNodeIndices: [Int]
        public var jointParentIndices: [Int?]

        public init(
            name: String,
            jointNames: [String],
            jointNodeIndices: [Int],
            jointParentIndices: [Int?]
        ) {
            self.name = name
            self.jointNames = jointNames
            self.jointNodeIndices = jointNodeIndices
            self.jointParentIndices = jointParentIndices
        }
    }

    /// Morph targets for one mesh. Names match RealityKit blend-shape offsets.
    public struct Morph: Sendable, Equatable {
        public var meshIndex: Int
        public var meshName: String
        public var targetNames: [String]

        public init(
            meshIndex: Int,
            meshName: String,
            targetNames: [String]
        ) {
            self.meshIndex = meshIndex
            self.meshName = meshName
            self.targetNames = targetNames
        }
    }

    public struct Animation: Sendable, Equatable {
        public var name: String
        public var duration: Double

        public init(
            name: String,
            duration: Double
        ) {
            self.name = name
            self.duration = duration
        }
    }
}
