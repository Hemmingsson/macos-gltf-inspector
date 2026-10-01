import Foundation

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

    /// Subtitle under the selected name in the inspector header.
    public var displayTitle: String {
        switch self {
        case .scene: "Scene"
        case .mesh: "Mesh"
        case .camera: "Camera"
        case .light: "Light"
        case .material: "Material"
        case .animation: "Animation"
        case .skin: "Skin"
        case .morph: "Morph"
        case .empty: "Group"
        }
    }
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
