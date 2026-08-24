import Foundation

// MARK: - Identity

/// What a row in the outliner is. Drives icon + tint (DESIGN.md: colour = meaning).
public enum NodeKind: String, Sendable, Hashable, Codable, CaseIterable {
    case scene
    case mesh
    case camera
    case light
    case material
    case animation
    case skin
    case morph
    /// A node that only carries a transform (glTF "empty").
    case empty
}

/// Addresses one row across every kind, so mesh 0 and material 0 never collide.
public struct NodeID: Sendable, Hashable, Codable {
    public var kind: NodeKind
    /// Index inside its own glTF array (`nodes`, `materials`, `animations`, …).
    public var index: Int

    public init(kind: NodeKind, index: Int) {
        self.kind = kind
        self.index = index
    }
}

// MARK: - Geometry primitives

public struct Vector3: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public static let zero = Vector3(x: 0, y: 0, z: 0)
    public static let one = Vector3(x: 1, y: 1, z: 1)

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Linear sRGB triple. Kept framework-free so engine adapters never hand the UI a `Color`.
public struct RGBColor: Sendable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public static let white = RGBColor(red: 1, green: 1, blue: 1)
    public static let black = RGBColor(red: 0, green: 0, blue: 0)

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// True when each channel is within `epsilon` of `other` (factor default checks).
    public func isApproximatelyEqual(to other: RGBColor, epsilon: Double = 0.004) -> Bool {
        abs(red - other.red) <= epsilon
            && abs(green - other.green) <= epsilon
            && abs(blue - other.blue) <= epsilon
    }
}

/// Authored TRS of one node. Rotation is Euler degrees — the inspector shows degrees.
public struct TransformInfo: Sendable, Hashable {
    public var position: Vector3
    public var rotationDegrees: Vector3
    public var scale: Vector3

    public init(position: Vector3, rotationDegrees: Vector3, scale: Vector3) {
        self.position = position
        self.rotationDegrees = rotationDegrees
        self.scale = scale
    }

    public static let identity = TransformInfo(position: .zero, rotationDegrees: .zero, scale: .one)
}

/// Bounding size of the model in metres plus where the authored origin sits inside it.
public struct Dimensions: Sendable, Hashable {
    public var width: Double
    public var height: Double
    public var depth: Double
    /// Authored origin relative to the model, in metres. Shown by the origin gizmo when Center is off.
    public var authoredOrigin: Vector3
    public var unit: String

    public init(width: Double, height: Double, depth: Double, authoredOrigin: Vector3 = .zero, unit: String = "m") {
        self.width = width
        self.height = height
        self.depth = depth
        self.authoredOrigin = authoredOrigin
        self.unit = unit
    }
}

// MARK: - Outliner

/// One node of the typed node tree. Children are nested — the outliner renders the tree.
public struct SceneNode: Sendable, Hashable, Identifiable {
    public var id: NodeID
    public var name: String
    public var children: [SceneNode]

    public var kind: NodeKind { id.kind }

    public init(id: NodeID, name: String, children: [SceneNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }

    public init(kind: NodeKind, index: Int, name: String, children: [SceneNode] = []) {
        self.init(id: NodeID(kind: kind, index: index), name: name, children: children)
    }
}

public struct SceneInfo: Sendable, Hashable, Identifiable {
    public var id: NodeID
    public var name: String
    /// Roots of this scene inside `SceneModel.nodeTree`.
    public var rootNodeIDs: [NodeID]

    public init(index: Int, name: String, rootNodeIDs: [NodeID] = []) {
        self.id = NodeID(kind: .scene, index: index)
        self.name = name
        self.rootNodeIDs = rootNodeIDs
    }
}

// MARK: - File contents

public struct CameraInfo: Sendable, Hashable, Identifiable {
    public var id: NodeID
    public var name: String
    public var projection: Projection
    /// Vertical field of view in degrees (perspective only).
    public var fieldOfViewDegrees: Double?
    /// Orthographic horizontal / vertical magnification (half-extents).
    public var xMag: Double?
    public var yMag: Double?
    public var zNear: Double
    public var zFar: Double?

    public init(
        index: Int,
        name: String,
        projection: Projection,
        fieldOfViewDegrees: Double? = nil,
        xMag: Double? = nil,
        yMag: Double? = nil,
        zNear: Double = 0.01,
        zFar: Double? = nil
    ) {
        self.id = NodeID(kind: .camera, index: index)
        self.name = name
        self.projection = projection
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.xMag = xMag
        self.yMag = yMag
        self.zNear = zNear
        self.zFar = zFar
    }
}

public struct LightInfo: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case directional
        case point
        case spot
    }

    public var id: NodeID
    public var name: String
    public var kind: Kind
    public var color: RGBColor
    /// glTF punctual intensity (lux for directional, candela otherwise).
    public var intensity: Double
    public var range: Double?
    /// Spot cone angles in degrees (`KHR_lights_punctual`).
    public var innerConeDegrees: Double?
    public var outerConeDegrees: Double?

    public init(
        index: Int,
        name: String,
        kind: Kind,
        color: RGBColor = .white,
        intensity: Double = 1,
        range: Double? = nil,
        innerConeDegrees: Double? = nil,
        outerConeDegrees: Double? = nil
    ) {
        self.id = NodeID(kind: .light, index: index)
        self.name = name
        self.kind = kind
        self.color = color
        self.intensity = intensity
        self.range = range
        self.innerConeDegrees = innerConeDegrees
        self.outerConeDegrees = outerConeDegrees
    }
}

/// A texture slot a material can carry. The inspector shows a chip per *present* map only.
public enum MaterialMap: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case baseColor
    case normal
    case metallicRoughness
    case occlusion
    case emissive
    case clearcoat
    case clearcoatRoughness
    case clearcoatNormal
    case specular
    case transmission

    public var id: Self { self }

    /// Full name, for menus and accessibility labels.
    public var title: String {
        switch self {
        case .baseColor: "Base Color"
        case .normal: "Normal"
        case .metallicRoughness: "Metallic Roughness"
        case .occlusion: "Ambient Occlusion"
        case .emissive: "Emissive"
        case .clearcoat: "Clearcoat"
        case .clearcoatRoughness: "Clearcoat Roughness"
        case .clearcoatNormal: "Clearcoat Normal"
        case .specular: "Specular"
        case .transmission: "Transmission"
        }
    }

    /// Chip label in the inspector (wireframe: Base · Normal · Rough · AO · Emissive).
    public var shortTitle: String {
        switch self {
        case .baseColor: "Base"
        case .normal: "Normal"
        case .metallicRoughness: "Rough"
        case .occlusion: "AO"
        case .emissive: "Emissive"
        case .clearcoat: "Coat"
        case .clearcoatRoughness: "Coat R"
        case .clearcoatNormal: "Coat N"
        case .specular: "Spec"
        case .transmission: "Trans"
        }
    }
}

/// One *present* texture binding on a material. Width/height and preview tint are optional —
/// the engine adapter can omit anything it does not know yet.
public struct MaterialTextureInfo: Sendable, Hashable, Identifiable {
    public var map: MaterialMap
    public var width: Int?
    public var height: Int?
    /// glTF `texCoord`. Inspector omits the UV set when this is 0.
    public var texCoord: Int
    /// Flat placeholder for the inspector swatch / map strip. Live engine can leave this nil
    /// and later supply an image handle without RealityKit types in the seam.
    public var previewColor: RGBColor?
    /// Small PNG thumb stamped at convert (max edge 96). Nil when decode failed / KTX2.
    public var thumbnailPNG: Data?

    public var id: MaterialMap { map }

    public init(
        map: MaterialMap,
        width: Int? = nil,
        height: Int? = nil,
        texCoord: Int = 0,
        previewColor: RGBColor? = nil,
        thumbnailPNG: Data? = nil
    ) {
        self.map = map
        self.width = width
        self.height = height
        self.texCoord = texCoord
        self.previewColor = previewColor
        self.thumbnailPNG = thumbnailPNG
    }

    /// `"2048×2048"` when both edges are known.
    public var sizeLabel: String? {
        guard let width, let height else { return nil }
        return "\(width)×\(height)"
    }
}

public struct MaterialInfo: Sendable, Hashable, Identifiable {
    public enum Workflow: String, Sendable, Hashable, Codable {
        case metallicRoughness
        /// Authored as KHR_materials_pbrSpecularGlossiness and converted on import.
        case specularGlossiness
        case unlit
    }

    public enum AlphaMode: String, Sendable, Hashable, Codable {
        case opaque
        case mask
        case blend
    }

    public var id: NodeID
    public var name: String
    public var workflow: Workflow
    public var alphaMode: AlphaMode
    public var isDoubleSided: Bool
    /// Only the maps that actually exist on the material. Kept in sync with `textures` when
    /// that list is non-empty so chips and map rows stay consistent.
    public var maps: Set<MaterialMap>
    /// Present map bindings with optional pixel size / UV / preview tint.
    public var textures: [MaterialTextureInfo]
    public var baseColorFactor: RGBColor?
    public var metallicFactor: Double?
    public var roughnessFactor: Double?
    public var emissiveFactor: RGBColor?
    /// KHR_materials_emissive_strength multiplier when present.
    public var emissiveStrength: Double?
    public var normalScale: Double?
    public var occlusionStrength: Double?
    /// Meaningful when `alphaMode == .mask`.
    public var alphaCutoff: Double?
    /// Mesh display names that reference this material (Materials-list selection).
    public var usedByMeshNames: [String]
    /// Optional triangle coverage across those meshes.
    public var usedByTriangleCount: Int?
    /// Distinct image count when known (may be lower than `textures.count` if maps share).
    public var uniqueTextureCount: Int?

    public init(
        index: Int,
        name: String,
        workflow: Workflow = .metallicRoughness,
        alphaMode: AlphaMode = .opaque,
        isDoubleSided: Bool = false,
        maps: Set<MaterialMap> = [],
        textures: [MaterialTextureInfo] = [],
        baseColorFactor: RGBColor? = nil,
        metallicFactor: Double? = nil,
        roughnessFactor: Double? = nil,
        emissiveFactor: RGBColor? = nil,
        emissiveStrength: Double? = nil,
        normalScale: Double? = nil,
        occlusionStrength: Double? = nil,
        alphaCutoff: Double? = nil,
        usedByMeshNames: [String] = [],
        usedByTriangleCount: Int? = nil,
        uniqueTextureCount: Int? = nil
    ) {
        self.id = NodeID(kind: .material, index: index)
        self.name = name
        self.workflow = workflow
        self.alphaMode = alphaMode
        self.isDoubleSided = isDoubleSided
        self.textures = textures
        self.baseColorFactor = baseColorFactor
        self.metallicFactor = metallicFactor
        self.roughnessFactor = roughnessFactor
        self.emissiveFactor = emissiveFactor
        self.emissiveStrength = emissiveStrength
        self.normalScale = normalScale
        self.occlusionStrength = occlusionStrength
        self.alphaCutoff = alphaCutoff
        self.usedByMeshNames = usedByMeshNames
        self.usedByTriangleCount = usedByTriangleCount
        self.uniqueTextureCount = uniqueTextureCount
        if textures.isEmpty {
            self.maps = maps
        } else {
            self.maps = Set(textures.map(\.map))
        }
    }

    /// Present maps in a stable display order.
    public var orderedMaps: [MaterialMap] {
        MaterialMap.allCases.filter(maps.contains)
    }

    /// Present texture rows in the same stable order as chips.
    public var orderedTextures: [MaterialTextureInfo] {
        let byMap = Dictionary(uniqueKeysWithValues: textures.map { ($0.map, $0) })
        return orderedMaps.compactMap { byMap[$0] }
    }
}

public struct AnimationInfo: Sendable, Hashable, Identifiable {
    public var id: NodeID
    public var name: String
    public var duration: TimeInterval

    public init(index: Int, name: String, duration: TimeInterval) {
        self.id = NodeID(kind: .animation, index: index)
        self.name = name
        self.duration = duration
    }
}

public struct SkinInfo: Sendable, Hashable, Identifiable {
    public var id: NodeID
    public var name: String
    public var jointCount: Int
    public var jointNames: [String]

    public init(index: Int, name: String, jointCount: Int, jointNames: [String] = []) {
        self.id = NodeID(kind: .skin, index: index)
        self.name = name
        self.jointCount = jointCount
        self.jointNames = jointNames
    }
}

public struct MorphInfo: Sendable, Hashable, Identifiable {
    public var id: NodeID
    /// Mesh that owns these targets.
    public var meshName: String
    /// Target names when authored, otherwise synthesised ("Target 1", …).
    public var targetNames: [String]

    public init(index: Int, meshName: String, targetNames: [String]) {
        self.id = NodeID(kind: .morph, index: index)
        self.meshName = meshName
        self.targetNames = targetNames
    }
}

/// Live morph-target weight for inspector sliders (host maps from `PreviewMorph`).
public struct MorphTargetControl: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var weight: Double

    public init(id: String, name: String, weight: Double) {
        self.id = id
        self.name = name
        self.weight = weight
    }
}

/// Per-node geometry facts (the inspector's Geometry section).
public struct GeometryInfo: Sendable, Hashable {
    public var triangleCount: Int
    public var vertexCount: Int
    public var uvSetCount: Int
    public var hasNormals: Bool
    public var hasTangents: Bool
    public var hasVertexColors: Bool

    public init(
        triangleCount: Int,
        vertexCount: Int,
        uvSetCount: Int = 1,
        hasNormals: Bool = true,
        hasTangents: Bool = false,
        hasVertexColors: Bool = false
    ) {
        self.triangleCount = triangleCount
        self.vertexCount = vertexCount
        self.uvSetCount = uvSetCount
        self.hasNormals = hasNormals
        self.hasTangents = hasTangents
        self.hasVertexColors = hasVertexColors
    }
}

/// Everything the inspector can show for one selection. Nil fields are fields the
/// node type does not have — the inspector hides them (DESIGN.md).
public struct NodeDetail: Sendable, Hashable, Identifiable {
    public var id: NodeID
    public var name: String
    public var transform: TransformInfo?
    /// True when the transform is the file's own, false when we re-centred/fitted it.
    public var isTransformAuthored: Bool
    public var geometry: GeometryInfo?
    public var material: MaterialInfo?
    public var light: LightInfo?
    public var camera: CameraInfo?
    public var animation: AnimationInfo?
    public var skin: SkinInfo?
    public var morph: MorphInfo?
    /// Scene root count when `kind == .scene`.
    public var sceneRootCount: Int?

    public var kind: NodeKind { id.kind }

    public init(
        id: NodeID,
        name: String,
        transform: TransformInfo? = nil,
        isTransformAuthored: Bool = true,
        geometry: GeometryInfo? = nil,
        material: MaterialInfo? = nil,
        light: LightInfo? = nil,
        camera: CameraInfo? = nil,
        animation: AnimationInfo? = nil,
        skin: SkinInfo? = nil,
        morph: MorphInfo? = nil,
        sceneRootCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.transform = transform
        self.isTransformAuthored = isTransformAuthored
        self.geometry = geometry
        self.material = material
        self.light = light
        self.camera = camera
        self.animation = animation
        self.skin = skin
        self.morph = morph
        self.sceneRootCount = sceneRootCount
    }
}

// MARK: - File-level facts

/// The inspector's File section.
public struct Stats: Sendable, Hashable {
    public var triangleCount: Int
    public var vertexCount: Int
    public var meshCount: Int
    public var materialCount: Int
    public var textureCount: Int
    /// Largest texture edge in pixels ("max 2048²"). Nil when there are no textures.
    public var maxTextureDimension: Int?
    public var animationCount: Int
    public var fileSizeBytes: Int64?
    public var hasVertexColors: Bool
    public var isRigged: Bool
    public var morphTargetCount: Int

    public init(
        triangleCount: Int = 0,
        vertexCount: Int = 0,
        meshCount: Int = 0,
        materialCount: Int = 0,
        textureCount: Int = 0,
        maxTextureDimension: Int? = nil,
        animationCount: Int = 0,
        fileSizeBytes: Int64? = nil,
        hasVertexColors: Bool = false,
        isRigged: Bool = false,
        morphTargetCount: Int = 0
    ) {
        self.triangleCount = triangleCount
        self.vertexCount = vertexCount
        self.meshCount = meshCount
        self.materialCount = materialCount
        self.textureCount = textureCount
        self.maxTextureDimension = maxTextureDimension
        self.animationCount = animationCount
        self.fileSizeBytes = fileSizeBytes
        self.hasVertexColors = hasVertexColors
        self.isRigged = isRigged
        self.morphTargetCount = morphTargetCount
    }
}

/// glTF-validator output, surfaced verbatim — "is the file wrong, or are we?".
public struct ValidationResult: Sendable, Hashable {
    public struct Issue: Sendable, Hashable, Identifiable {
        public enum Severity: String, Sendable, Hashable, Codable, CaseIterable {
            case error
            case warning
            case info
            case hint
        }

        public var severity: Severity
        public var message: String
        /// glTF JSON pointer the validator blamed, when it gave one.
        public var pointer: String?

        public var id: String { "\(severity.rawValue)|\(pointer ?? "")|\(message)" }

        public init(severity: Severity, message: String, pointer: String? = nil) {
            self.severity = severity
            self.message = message
            self.pointer = pointer
        }
    }

    public var issues: [Issue]
    /// "glTF 2.0" — shown next to the clean badge.
    public var formatLabel: String
    /// Pending means the Khronos run has not finished; unavailable is a hard skip/fail.
    public var status: Status

    public enum Status: String, Sendable, Hashable {
        case pending
        case ready
        case unavailable
    }

    public init(
        issues: [Issue] = [],
        formatLabel: String = "glTF 2.0",
        status: Status = .ready
    ) {
        self.issues = issues
        self.formatLabel = formatLabel
        self.status = status
    }

    public var errorCount: Int { issues.filter { $0.severity == .error }.count }
    public var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    /// Green “Valid” only after a successful run with no errors or warnings.
    public var isClean: Bool { status == .ready && errorCount == 0 && warningCount == 0 }
}

/// "What our pipeline did" — every silent change we made on import.
public struct PipelineReport: Sendable, Hashable {
    public struct Entry: Sendable, Hashable, Identifiable {
        public enum Kind: Sendable, Hashable {
            /// Conversion / dequant steps — “we did work”.
            case conversion
            /// Status line (file lights / studio IBL).
            case lighting
        }

        public var kind: Kind
        public var title: String
        public var detail: String?

        public var id: String { detail.map { "\(title)|\($0)" } ?? title }

        public init(kind: Kind = .conversion, title: String, detail: String? = nil) {
            self.kind = kind
            self.title = title
            self.detail = detail
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }
}

/// Convert losses — “not rendered as authored”. Separate from Khronos validation.
public struct ConvertProblemList: Sendable, Hashable {
    public struct Entry: Sendable, Hashable, Identifiable {
        public enum Severity: String, Sendable, Hashable {
            case error
            case warning
        }

        public var severity: Severity
        public var title: String
        public var code: String

        public var id: String { "\(code)|\(severity.rawValue)|\(title)" }

        public init(severity: Severity, title: String, code: String) {
            self.severity = severity
            self.title = title
            self.code = code
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var errorCount: Int { entries.filter { $0.severity == .error }.count }
    public var warningCount: Int { entries.filter { $0.severity == .warning }.count }
}

// MARK: - Viewport vocabulary

/// Backdrop behind the model. Mirrors the host's stored backgrounds.
public enum BackdropStyle: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case window
    case white
    case dark

    public var id: Self { self }

    public var title: String {
        switch self {
        case .window: "None"
        case .white: "White"
        case .dark: "Dark"
        }
    }
}

/// A render channel the view-mode menu can offer. Only channels the file actually
/// has appear (`Availability.availableDebugChannels`).
public enum DebugChannel: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case baseColor
    case metallic
    case roughness
    case normals
    case tangents
    case textureCoordinates
    case ambientOcclusion
    case emissive
    case alpha
    case specular
    case clearcoat
    case clearcoatRoughness
    case clearcoatNormal

    public var id: Self { self }

    public var title: String {
        switch self {
        case .baseColor: "Base Color"
        case .metallic: "Metallic"
        case .roughness: "Roughness"
        case .normals: "Normals"
        case .tangents: "Tangents"
        case .textureCoordinates: "UVs"
        case .ambientOcclusion: "Ambient Occlusion"
        case .emissive: "Emissive"
        case .alpha: "Alpha"
        case .specular: "Specular"
        case .clearcoat: "Clearcoat"
        case .clearcoatRoughness: "Clearcoat Roughness"
        case .clearcoatNormal: "Clearcoat Normal"
        }
    }
}

/// How the canvas draws the model. Menu shows full names, never abbreviations.
public enum ViewMode: Sendable, Hashable, Identifiable {
    case shaded
    case wireframe
    case channel(DebugChannel)

    public var id: String {
        switch self {
        case .shaded: "shaded"
        case .wireframe: "wireframe"
        case .channel(let channel): "channel.\(channel.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .shaded: "Shaded"
        case .wireframe: "Wireframe"
        case .channel(let channel): channel.title
        }
    }

    /// Always-available modes; channels are appended per file.
    public static let base: [ViewMode] = [.shaded, .wireframe]
}

public enum Projection: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case perspective
    case orthographic

    public var id: Self { self }

    public var title: String {
        switch self {
        case .perspective: "Perspective"
        case .orthographic: "Orthographic"
        }
    }
}

/// Canned camera angles. File cameras are separate (`SceneModel.cameras`).
public enum CameraPreset: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case front
    case back
    case left
    case right
    case top
    case bottom
    case isometric

    public var id: Self { self }

    public var title: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        case .isometric: "Isometric"
        }
    }
}

/// What the lighting popover edits.
/// The bundled image-based lighting environments.
///
/// glTF files carry no environment of their own, so what a model looks like is partly the app's
/// choice. Naming that choice and putting it on screen is the honest option: a user comparing
/// against another tool needs to know what they are comparing.
public enum StudioEnvironment: String, Sendable, Hashable, CaseIterable, Identifiable {
    case neutral
    case field
    case colorfulStudio = "Colorful_Studio"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neutral: "Neutral"
        case .field: "Field"
        case .colorfulStudio: "Studio"
        }
    }
}

/// Tone mapping curve applied on the way to the screen.
///
/// `neutral` is the default on purpose: Khronos designed PBR Neutral for asset review because it
/// distorts authored colour least. ACES looks more cinematic and is the wrong default for a tool
/// whose job is telling you what is actually in the file.
public enum ToneMapping: String, Sendable, Hashable, CaseIterable, Identifiable {
    case neutral
    case acesHill
    case acesNarkowicz
    case linear

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neutral: "Neutral"
        case .acesHill: "ACES"
        case .acesNarkowicz: "ACES Fast"
        case .linear: "Linear"
        }
    }
}

public struct LightingSettings: Sendable, Hashable {
    /// Exposure compensation in stops.
    public var exposure: Double
    /// Environment yaw in degrees.
    public var environmentRotationDegrees: Double
    /// Use the file's punctual lights (only meaningful when `Availability.hasLights`).
    public var usesFileLights: Bool
    /// Use the bundled studio IBL.
    public var usesStudioEnvironment: Bool
    /// Which bundled IBL lights the model.
    public var environment: StudioEnvironment
    /// Tone mapping curve.
    public var toneMapping: ToneMapping

    public static let standard = LightingSettings(
        exposure: 0,
        environmentRotationDegrees: 0,
        usesFileLights: false,
        usesStudioEnvironment: true,
        environment: .neutral,
        toneMapping: .neutral
    )

    public init(
        exposure: Double,
        environmentRotationDegrees: Double,
        usesFileLights: Bool,
        usesStudioEnvironment: Bool,
        environment: StudioEnvironment = .neutral,
        toneMapping: ToneMapping = .neutral
    ) {
        self.exposure = exposure
        self.environmentRotationDegrees = environmentRotationDegrees
        self.usesFileLights = usesFileLights
        self.environment = environment
        self.toneMapping = toneMapping
        self.usesStudioEnvironment = usesStudioEnvironment
    }
}
