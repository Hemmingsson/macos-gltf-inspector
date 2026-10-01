import Foundation

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

/// One *present* texture binding on a material. Width/height are optional —
/// the engine adapter can omit anything it does not know yet.
public struct MaterialTextureInfo: Sendable, Hashable, Identifiable {
    public var map: MaterialMap
    public var width: Int?
    public var height: Int?
    /// glTF `texCoord`. Inspector omits the UV set when this is 0.
    public var texCoord: Int
    /// Small PNG thumb stamped at convert (max edge 96). Nil when decode failed / KTX2.
    public var thumbnailPNG: Data?

    public var id: MaterialMap { map }

    public init(
        map: MaterialMap,
        width: Int? = nil,
        height: Int? = nil,
        texCoord: Int = 0,
        thumbnailPNG: Data? = nil
    ) {
        self.map = map
        self.width = width
        self.height = height
        self.texCoord = texCoord
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
    public var normalScale: Double?
    public var occlusionStrength: Double?
    /// Meaningful when `alphaMode == .mask`.
    public var alphaCutoff: Double?
    /// Mesh display names that reference this material (Materials-list selection).
    public var usedByMeshNames: [String]

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
        normalScale: Double? = nil,
        occlusionStrength: Double? = nil,
        alphaCutoff: Double? = nil,
        usedByMeshNames: [String] = []
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
        self.normalScale = normalScale
        self.occlusionStrength = occlusionStrength
        self.alphaCutoff = alphaCutoff
        self.usedByMeshNames = usedByMeshNames
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
