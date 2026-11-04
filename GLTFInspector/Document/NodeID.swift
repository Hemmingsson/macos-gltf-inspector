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
