import Foundation

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
        }
    }
}

/// One *present* texture binding on a material. Width/height are optional —
/// the engine adapter can omit anything it does not know yet.
struct MaterialTextureInfo: Sendable, Hashable, Identifiable {
    var map: MaterialMap
    var width: Int?
    var height: Int?
    /// glTF `texCoord`. Inspector omits the UV set when this is 0.
    var texCoord: Int
    /// Small PNG thumb decoded from the file (max edge 96). Nil when decode failed / KTX2.
    var thumbnailPNG: Data?

    var id: MaterialMap { map }

    init(
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
    var sizeLabel: String? {
        guard let width, let height else { return nil }
        return "\(width)×\(height)"
    }
}

struct MaterialInfo: Sendable, Hashable, Identifiable {
    enum Workflow: String, Sendable, Hashable, Codable {
        case metallicRoughness
        /// Authored as KHR_materials_pbrSpecularGlossiness.
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
    /// `KHR_materials_emissive_strength`. Nil when the extension is absent (spec default 1).
    var emissiveStrength: Double?
    var normalScale: Double?
    var occlusionStrength: Double?
    /// Meaningful when `alphaMode == .mask`.
    var alphaCutoff: Double?
    /// Mesh display names that reference this material (Materials-list selection).
    var usedByMeshNames: [String]

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
        self.emissiveStrength = emissiveStrength
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
    var orderedMaps: [MaterialMap] {
        MaterialMap.allCases.filter(maps.contains)
    }

    /// Present texture rows in the same stable order as chips.
    var orderedTextures: [MaterialTextureInfo] {
        let byMap = Dictionary(uniqueKeysWithValues: textures.map { ($0.map, $0) })
        return orderedMaps.compactMap { byMap[$0] }
    }
}
