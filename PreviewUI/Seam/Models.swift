import Foundation

// MARK: - Identity

/// What a row in the outliner is. Drives icon + tint (DESIGN.md: colour = meaning).
enum NodeKind: String, Sendable, Hashable, Codable, CaseIterable {
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
struct NodeID: Sendable, Hashable, Codable {
    var kind: NodeKind
    /// Index inside its own glTF array (`nodes`, `materials`, `animations`, …).
    var index: Int

    init(kind: NodeKind, index: Int) {
        self.kind = kind
        self.index = index
    }
}

// MARK: - Geometry primitives

struct Vector3: Sendable, Hashable, Codable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)
    static let one = Vector3(x: 1, y: 1, z: 1)

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Linear sRGB triple. Kept framework-free so engine adapters never hand the UI a `Color`.
struct RGBColor: Sendable, Hashable, Codable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = RGBColor(red: 1, green: 1, blue: 1)
    static let black = RGBColor(red: 0, green: 0, blue: 0)

    /// True when each channel is within `epsilon` of `other` (factor default checks).
    func isApproximatelyEqual(to other: RGBColor, epsilon: Double = 0.004) -> Bool {
        abs(red - other.red) <= epsilon
            && abs(green - other.green) <= epsilon
            && abs(blue - other.blue) <= epsilon
    }
}

/// Authored TRS of one node. Rotation is Euler degrees — the inspector shows degrees.
struct TransformInfo: Sendable, Hashable {
    var position: Vector3
    var rotationDegrees: Vector3
    var scale: Vector3

    static let identity = TransformInfo(position: .zero, rotationDegrees: .zero, scale: .one)
}

/// Bounding size of the model in metres plus where the authored origin sits inside it.
struct Dimensions: Sendable, Hashable {
    var width: Double
    var height: Double
    var depth: Double
    /// Authored origin relative to the model, in metres. Shown by the origin gizmo when Center is off.
    var authoredOrigin: Vector3
    var unit: String

    init(width: Double, height: Double, depth: Double, authoredOrigin: Vector3 = .zero, unit: String = "m") {
        self.width = width
        self.height = height
        self.depth = depth
        self.authoredOrigin = authoredOrigin
        self.unit = unit
    }
}

// MARK: - Outliner

/// One node of the typed node tree. Children are nested — the outliner renders the tree.
struct SceneNode: Sendable, Hashable, Identifiable {
    var id: NodeID
    var name: String
    var children: [SceneNode]

    var kind: NodeKind { id.kind }

    init(id: NodeID, name: String, children: [SceneNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }

    init(kind: NodeKind, index: Int, name: String, children: [SceneNode] = []) {
        self.init(id: NodeID(kind: kind, index: index), name: name, children: children)
    }
}

struct SceneInfo: Sendable, Hashable, Identifiable {
    var id: NodeID
    var name: String
    /// Roots of this scene inside `SceneModel.nodeTree`.
    var rootNodeIDs: [NodeID]

    init(index: Int, name: String, rootNodeIDs: [NodeID] = []) {
        self.id = NodeID(kind: .scene, index: index)
        self.name = name
        self.rootNodeIDs = rootNodeIDs
    }
}

// MARK: - File contents

struct CameraInfo: Sendable, Hashable, Identifiable {
    var id: NodeID
    var name: String
    var projection: Projection
    /// Vertical field of view in degrees (perspective only).
    var fieldOfViewDegrees: Double?
    var zNear: Double
    var zFar: Double?

    init(
        index: Int,
        name: String,
        projection: Projection,
        fieldOfViewDegrees: Double? = nil,
        zNear: Double = 0.01,
        zFar: Double? = nil
    ) {
        self.id = NodeID(kind: .camera, index: index)
        self.name = name
        self.projection = projection
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.zNear = zNear
        self.zFar = zFar
    }
}

struct LightInfo: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case directional
        case point
        case spot
    }

    var id: NodeID
    var name: String
    var kind: Kind
    var color: RGBColor
    /// glTF punctual intensity (lux for directional, candela otherwise).
    var intensity: Double
    var range: Double?

    init(
        index: Int,
        name: String,
        kind: Kind,
        color: RGBColor = .white,
        intensity: Double = 1,
        range: Double? = nil
    ) {
        self.id = NodeID(kind: .light, index: index)
        self.name = name
        self.kind = kind
        self.color = color
        self.intensity = intensity
        self.range = range
    }
}

/// A texture slot a material can carry. The inspector shows a chip per *present* map only.
enum MaterialMap: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
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

    var id: Self { self }

    /// Full name, for menus and accessibility labels.
    var title: String {
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
    var shortTitle: String {
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
struct MaterialTextureInfo: Sendable, Hashable, Identifiable {
    var map: MaterialMap
    var width: Int?
    var height: Int?
    /// glTF `texCoord`. Inspector omits the UV set when this is 0.
    var texCoord: Int
    /// Flat placeholder for the inspector swatch / map strip. Live engine can leave this nil
    /// and later supply an image handle without RealityKit types in the seam.
    var previewColor: RGBColor?

    var id: MaterialMap { map }

    init(
        map: MaterialMap,
        width: Int? = nil,
        height: Int? = nil,
        texCoord: Int = 0,
        previewColor: RGBColor? = nil
    ) {
        self.map = map
        self.width = width
        self.height = height
        self.texCoord = texCoord
        self.previewColor = previewColor
    }

    /// `"2048×2048"` when both edges are known.
    var sizeLabel: String? {
        guard let width, let height else { return nil }
        return "\(width)×\(height)"
    }
}

struct MaterialInfo: Sendable, Hashable, Identifiable {
    enum Workflow: String, Sendable, Hashable, Codable {
        case metallicRoughness
        /// Authored as KHR_materials_pbrSpecularGlossiness and converted on import.
        case specularGlossiness
        case unlit
    }

    enum AlphaMode: String, Sendable, Hashable, Codable {
        case opaque
        case mask
        case blend
    }

    var id: NodeID
    var name: String
    var workflow: Workflow
    var alphaMode: AlphaMode
    var isDoubleSided: Bool
    /// Only the maps that actually exist on the material. Kept in sync with `textures` when
    /// that list is non-empty so chips and map rows stay consistent.
    var maps: Set<MaterialMap>
    /// Present map bindings with optional pixel size / UV / preview tint.
    var textures: [MaterialTextureInfo]
    var baseColorFactor: RGBColor?
    var metallicFactor: Double?
    var roughnessFactor: Double?
    var emissiveFactor: RGBColor?
    /// KHR_materials_emissive_strength multiplier when present.
    var emissiveStrength: Double?
    var normalScale: Double?
    var occlusionStrength: Double?
    /// Meaningful when `alphaMode == .mask`.
    var alphaCutoff: Double?
    /// Mesh display names that reference this material (Materials-list selection).
    var usedByMeshNames: [String]
    /// Optional triangle coverage across those meshes.
    var usedByTriangleCount: Int?
    /// Distinct image count when known (may be lower than `textures.count` if maps share).
    var uniqueTextureCount: Int?

    init(
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
    var orderedMaps: [MaterialMap] {
        MaterialMap.allCases.filter(maps.contains)
    }

    /// Present texture rows in the same stable order as chips.
    var orderedTextures: [MaterialTextureInfo] {
        let byMap = Dictionary(uniqueKeysWithValues: textures.map { ($0.map, $0) })
        return orderedMaps.compactMap { byMap[$0] }
    }
}

struct AnimationInfo: Sendable, Hashable, Identifiable {
    var id: NodeID
    var name: String
    var duration: TimeInterval

    init(index: Int, name: String, duration: TimeInterval) {
        self.id = NodeID(kind: .animation, index: index)
        self.name = name
        self.duration = duration
    }
}

struct SkinInfo: Sendable, Hashable, Identifiable {
    var id: NodeID
    var name: String
    var jointCount: Int

    init(index: Int, name: String, jointCount: Int) {
        self.id = NodeID(kind: .skin, index: index)
        self.name = name
        self.jointCount = jointCount
    }
}

struct MorphInfo: Sendable, Hashable, Identifiable {
    var id: NodeID
    /// Mesh that owns these targets.
    var meshName: String
    /// Target names when authored, otherwise synthesised ("Target 1", …).
    var targetNames: [String]

    init(index: Int, meshName: String, targetNames: [String]) {
        self.id = NodeID(kind: .morph, index: index)
        self.meshName = meshName
        self.targetNames = targetNames
    }
}

/// Live morph-target weight for inspector sliders (host maps from `PreviewMorph`).
struct MorphTargetControl: Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var weight: Double
}

/// Per-node geometry facts (the inspector's Geometry section).
struct GeometryInfo: Sendable, Hashable {
    var triangleCount: Int
    var vertexCount: Int
    var uvSetCount: Int
    var hasNormals: Bool
    var hasTangents: Bool
    var hasVertexColors: Bool

    init(
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
struct NodeDetail: Sendable, Hashable, Identifiable {
    var id: NodeID
    var name: String
    var transform: TransformInfo?
    /// True when the transform is the file's own, false when we re-centred/fitted it.
    var isTransformAuthored: Bool
    var geometry: GeometryInfo?
    var material: MaterialInfo?
    var light: LightInfo?
    var camera: CameraInfo?
    var animation: AnimationInfo?

    var kind: NodeKind { id.kind }

    init(
        id: NodeID,
        name: String,
        transform: TransformInfo? = nil,
        isTransformAuthored: Bool = true,
        geometry: GeometryInfo? = nil,
        material: MaterialInfo? = nil,
        light: LightInfo? = nil,
        camera: CameraInfo? = nil,
        animation: AnimationInfo? = nil
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
    }
}

// MARK: - File-level facts

/// The inspector's File section.
struct Stats: Sendable, Hashable {
    var triangleCount: Int
    var vertexCount: Int
    var meshCount: Int
    var materialCount: Int
    var textureCount: Int
    /// Largest texture edge in pixels ("max 2048²"). Nil when there are no textures.
    var maxTextureDimension: Int?
    var animationCount: Int
    var fileSizeBytes: Int64?
    var hasVertexColors: Bool
    var isRigged: Bool
    var morphTargetCount: Int

    init(
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
struct ValidationResult: Sendable, Hashable {
    struct Issue: Sendable, Hashable, Identifiable {
        enum Severity: String, Sendable, Hashable, Codable, CaseIterable {
            case error
            case warning
            case info
            case hint
        }

        var severity: Severity
        var message: String
        /// glTF JSON pointer the validator blamed, when it gave one.
        var pointer: String?

        var id: String { "\(severity.rawValue)|\(pointer ?? "")|\(message)" }

        init(severity: Severity, message: String, pointer: String? = nil) {
            self.severity = severity
            self.message = message
            self.pointer = pointer
        }
    }

    var issues: [Issue]
    /// "glTF 2.0" — shown next to the clean badge.
    var formatLabel: String
    /// Pending means the Khronos run has not finished; unavailable is a hard skip/fail.
    var status: Status

    enum Status: String, Sendable, Hashable {
        case pending
        case ready
        case unavailable
    }

    init(
        issues: [Issue] = [],
        formatLabel: String = "glTF 2.0",
        status: Status = .ready
    ) {
        self.issues = issues
        self.formatLabel = formatLabel
        self.status = status
    }

    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    /// Green “Valid” only after a successful run with no errors or warnings.
    var isClean: Bool { status == .ready && errorCount == 0 && warningCount == 0 }
}

/// "What our pipeline did" — every silent change we made on import.
struct PipelineReport: Sendable, Hashable {
    struct Entry: Sendable, Hashable, Identifiable {
        enum Kind: Sendable, Hashable {
            /// Conversion / dequant steps — “we did work”.
            case conversion
            /// Status line (file lights / studio IBL).
            case lighting
        }

        var kind: Kind
        var title: String
        var detail: String?

        var id: String { detail.map { "\(title)|\($0)" } ?? title }

        init(kind: Kind = .conversion, title: String, detail: String? = nil) {
            self.kind = kind
            self.title = title
            self.detail = detail
        }
    }

    var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    var isEmpty: Bool { entries.isEmpty }
}

/// Convert losses — “not rendered as authored”. Separate from Khronos validation.
struct ConvertProblemList: Sendable, Hashable {
    struct Entry: Sendable, Hashable, Identifiable {
        enum Severity: String, Sendable, Hashable {
            case error
            case warning
        }

        var severity: Severity
        var title: String
        var code: String

        var id: String { "\(code)|\(severity.rawValue)|\(title)" }

        init(severity: Severity, title: String, code: String) {
            self.severity = severity
            self.title = title
            self.code = code
        }
    }

    var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    var isEmpty: Bool { entries.isEmpty }
    var errorCount: Int { entries.filter { $0.severity == .error }.count }
    var warningCount: Int { entries.filter { $0.severity == .warning }.count }
}

// MARK: - Viewport vocabulary

/// Backdrop behind the model. Mirrors the host's stored backgrounds.
enum BackdropStyle: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case window
    case white
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .window: "None"
        case .white: "White"
        case .dark: "Dark"
        }
    }
}

/// A render channel the view-mode menu can offer. Only channels the file actually
/// has appear (`Availability.availableDebugChannels`).
enum DebugChannel: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
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

    var id: Self { self }

    var title: String {
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
enum ViewMode: Sendable, Hashable, Identifiable {
    case shaded
    case wireframe
    case channel(DebugChannel)

    var id: String {
        switch self {
        case .shaded: "shaded"
        case .wireframe: "wireframe"
        case .channel(let channel): "channel.\(channel.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .shaded: "Shaded"
        case .wireframe: "Wireframe"
        case .channel(let channel): channel.title
        }
    }

    /// Always-available modes; channels are appended per file.
    static let base: [ViewMode] = [.shaded, .wireframe]
}

enum Projection: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case perspective
    case orthographic

    var id: Self { self }

    var title: String {
        switch self {
        case .perspective: "Perspective"
        case .orthographic: "Orthographic"
        }
    }
}

/// Canned camera angles. File cameras are separate (`SceneModel.cameras`).
enum CameraPreset: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case front
    case back
    case left
    case right
    case top
    case bottom
    case isometric

    var id: Self { self }

    var title: String {
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
struct LightingSettings: Sendable, Hashable {
    /// Exposure compensation in stops.
    var exposure: Double
    /// Environment yaw in degrees.
    var environmentRotationDegrees: Double
    /// Use the file's punctual lights (only meaningful when `Availability.hasLights`).
    var usesFileLights: Bool
    /// Use the bundled studio IBL.
    var usesStudioEnvironment: Bool

    static let standard = LightingSettings(
        exposure: 0,
        environmentRotationDegrees: 0,
        usesFileLights: false,
        usesStudioEnvironment: true
    )

    init(
        exposure: Double,
        environmentRotationDegrees: Double,
        usesFileLights: Bool,
        usesStudioEnvironment: Bool
    ) {
        self.exposure = exposure
        self.environmentRotationDegrees = environmentRotationDegrees
        self.usesFileLights = usesFileLights
        self.usesStudioEnvironment = usesStudioEnvironment
    }
}
