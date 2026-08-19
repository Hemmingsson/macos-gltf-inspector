import RealityKit

struct GLTFNodeIDComponent: Component, Codable {
    var nodeIndex: Int
}

/// Convert-time RealityKit materials in glTF material-index order.
struct GLTFMaterialTableComponent: Component {
    var materials: [any RealityKit.Material]
}
