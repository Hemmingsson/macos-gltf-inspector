import Foundation

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
    public var hasTangents: Bool
    public var hasVertexColors: Bool

    public init(
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

    /// Any inspector section besides the header. Keep in sync with `RightInspector` body.
    public var hasBody: Bool {
        transform != nil || geometry != nil || material != nil || light != nil
            || camera != nil || animation != nil || skin != nil || morph != nil
            || sceneRootCount != nil
    }

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
