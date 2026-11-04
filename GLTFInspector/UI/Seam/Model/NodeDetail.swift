import Foundation

struct CameraInfo: Sendable, Hashable, Identifiable {
    var id: NodeID
    var name: String
    var isOrthographic: Bool
    /// Vertical field of view in degrees (perspective only).
    var fieldOfViewDegrees: Double?
    /// Orthographic horizontal / vertical magnification (half-extents).
    var xMag: Double?
    var yMag: Double?
    var zNear: Double
    var zFar: Double?

    init(
        index: Int,
        name: String,
        isOrthographic: Bool,
        fieldOfViewDegrees: Double? = nil,
        xMag: Double? = nil,
        yMag: Double? = nil,
        zNear: Double = 0.01,
        zFar: Double? = nil
    ) {
        self.id = NodeID(kind: .camera, index: index)
        self.name = name
        self.isOrthographic = isOrthographic
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.xMag = xMag
        self.yMag = yMag
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
    /// glTF punctual intensity (lux for directional, candela otherwise).
    var intensity: Double
    var range: Double?
    /// Spot cone angles in degrees (`KHR_lights_punctual`).
    var innerConeDegrees: Double?
    var outerConeDegrees: Double?

    init(
        index: Int,
        name: String,
        kind: Kind,
        intensity: Double = 1,
        range: Double? = nil,
        innerConeDegrees: Double? = nil,
        outerConeDegrees: Double? = nil
    ) {
        self.id = NodeID(kind: .light, index: index)
        self.name = name
        self.kind = kind
        self.intensity = intensity
        self.range = range
        self.innerConeDegrees = innerConeDegrees
        self.outerConeDegrees = outerConeDegrees
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
    var jointNames: [String]

    init(index: Int, name: String, jointCount: Int, jointNames: [String] = []) {
        self.id = NodeID(kind: .skin, index: index)
        self.name = name
        self.jointCount = jointCount
        self.jointNames = jointNames
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

/// Per-node geometry facts (the inspector's Geometry section).
struct GeometryInfo: Sendable, Hashable {
    var triangleCount: Int
    var vertexCount: Int
    var uvSetCount: Int
    var hasTangents: Bool
    var hasVertexColors: Bool

    init(
        triangleCount: Int,
        vertexCount: Int,
        uvSetCount: Int = 1,
        hasTangents: Bool = false,
        hasVertexColors: Bool = false
    ) {
        self.triangleCount = triangleCount
        self.vertexCount = vertexCount
        self.uvSetCount = uvSetCount
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
    var geometry: GeometryInfo?
    var material: MaterialInfo?
    var light: LightInfo?
    var camera: CameraInfo?
    var animation: AnimationInfo?
    var skin: SkinInfo?
    var morph: MorphInfo?
    /// Scene root count when `kind == .scene`.
    var sceneRootCount: Int?

    var kind: NodeKind { id.kind }

    /// Any inspector section besides the header. Keep in sync with `RightInspector` body.
    var hasBody: Bool {
        transform != nil || geometry != nil || material != nil || light != nil
            || camera != nil || animation != nil || skin != nil || morph != nil
            || sceneRootCount != nil
    }

    init(
        id: NodeID,
        name: String,
        transform: TransformInfo? = nil,
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
