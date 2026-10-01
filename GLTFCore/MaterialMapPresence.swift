import Foundation

/// Canonical texture-map presence for one material.
/// Sidebar map chips and `PreviewDebugMode` material scans share this shape.
public struct MaterialMapPresence: Sendable, Equatable {
    public var baseColor = false
    public var normal = false
    public var metallicRoughness = false
    public var occlusion = false
    public var emissive = false
    public var specular = false
    public var clearcoat = false
    public var clearcoatRoughness = false
    public var clearcoatNormal = false

    /// JSON material → map presence, read from the one binding table
    /// (`GLTFDocumentJSON.textureRefs`) the inspector's texture slots use.
    static func from(json material: [String: Any]) -> MaterialMapPresence {
        var maps = MaterialMapPresence()
        for ref in GLTFDocumentJSON.textureRefs(material) {
            switch ref.kind {
            case .baseColor: maps.baseColor = true
            case .normal: maps.normal = true
            case .metallicRoughness: maps.metallicRoughness = true
            case .occlusion: maps.occlusion = true
            case .emissive: maps.emissive = true
            case .specular: maps.specular = true
            case .clearcoat: maps.clearcoat = true
            case .clearcoatRoughness: maps.clearcoatRoughness = true
            case .clearcoatNormal: maps.clearcoatNormal = true
            }
        }
        return maps
    }
}
