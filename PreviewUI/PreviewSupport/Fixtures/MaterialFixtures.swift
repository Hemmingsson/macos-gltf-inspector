import Foundation

/// Static material rows for inspector previews — no disk I/O.
public enum MaterialFixtures {
  public static let cube = MaterialInfo(
    index: 0,
    name: "CubeMaterial",
    workflow: .metallicRoughness,
    alphaMode: .opaque,
    maps: [.baseColor, .metallicRoughness],
    textures: [
      MaterialTextureInfo(
        map: .baseColor,
        width: 256,
        height: 256
      ),
      MaterialTextureInfo(map: .metallicRoughness, width: 256, height: 256)
    ],
    baseColorFactor: RGBColor(red: 1, green: 1, blue: 1),
    metallicFactor: 0,
    roughnessFactor: 0.72,
    usedByMeshNames: ["Cube"]
  )

  public static let fullPBR = MaterialInfo(
    index: 1,
    name: "Hero",
    workflow: .metallicRoughness,
    alphaMode: .blend,
    isDoubleSided: true,
    maps: [.baseColor, .normal, .metallicRoughness, .occlusion, .emissive],
    textures: [
      MaterialTextureInfo(map: .baseColor, width: 2048, height: 2048),
      MaterialTextureInfo(map: .normal, width: 2048, height: 2048),
      MaterialTextureInfo(map: .metallicRoughness, width: 2048, height: 2048),
      MaterialTextureInfo(map: .occlusion, width: 1024, height: 1024),
      MaterialTextureInfo(map: .emissive, width: 512, height: 512)
    ],
    baseColorFactor: RGBColor(red: 1, green: 1, blue: 1),
    metallicFactor: 1,
    roughnessFactor: 0.35,
    emissiveFactor: RGBColor(red: 1, green: 0.4, blue: 0.05),
    normalScale: 1,
    occlusionStrength: 1,
    usedByMeshNames: ["Body", "Trim"]
  )

  public static let baseColorOnly = MaterialInfo(
    index: 3,
    name: "BaseColorOnly",
    workflow: .metallicRoughness,
    maps: [.baseColor],
    textures: [
      MaterialTextureInfo(map: .baseColor, width: 128, height: 128)
    ],
    baseColorFactor: RGBColor(red: 0.8, green: 0.8, blue: 0.82),
    metallicFactor: 0,
    roughnessFactor: 1,
    usedByMeshNames: ["Plane"]
  )
}
