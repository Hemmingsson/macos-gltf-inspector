import Foundation

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

    /// Subtitle under the selected name in the inspector header.
    var displayTitle: String {
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
struct NodeID: Sendable, Hashable, Codable {
    var kind: NodeKind
    /// Index inside its own glTF array (`nodes`, `materials`, `animations`, …).
    var index: Int

    init(kind: NodeKind, index: Int) {
        self.kind = kind
        self.index = index
    }
}

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

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

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

    init(position: Vector3, rotationDegrees: Vector3, scale: Vector3) {
        self.position = position
        self.rotationDegrees = rotationDegrees
        self.scale = scale
    }

    static let identity = TransformInfo(position: .zero, rotationDegrees: .zero, scale: .one)
}

/// Bounding size of the model in metres plus where the authored origin sits inside it.
struct Dimensions: Sendable, Hashable {
    var width: Double
    var height: Double
    var depth: Double
    /// Authored origin relative to the model, in metres. Shown by the origin gizmo when Center is off.
    var authoredOrigin: Vector3

    init(width: Double, height: Double, depth: Double, authoredOrigin: Vector3 = .zero) {
        self.width = width
        self.height = height
        self.depth = depth
        self.authoredOrigin = authoredOrigin
    }
}
