import Foundation

// Usage: swift encode-bake.swift bake.json field.metalibl
struct Bake: Codable {
    let version: Int
    let upstream: String
    let environment: String
    let intensityScale: Float
    let mipCount: Int
    let textures: [Texture]
}
struct Texture: Codable {
    let name: String
    let size: Int
    let cube: Bool
    let levels: [Level]
}
struct Level: Codable {
    let mip: Int
    let face: Int
    let width: Int
    let height: Int
    let data: Data
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let bake = try JSONDecoder().decode(Bake.self, from: Data(contentsOf: input))
precondition(bake.version == 1 && bake.upstream == "863b981" && bake.environment == "field")
precondition(bake.intensityScale.isFinite && bake.intensityScale > 0 && bake.mipCount == 5)
precondition(Set(bake.textures.map(\.name)) == Set(["diffuse", "specular", "sheen"]))
for texture in bake.textures {
    precondition(texture.size == 256 && texture.cube)
    precondition(texture.levels.count == (texture.name == "diffuse" ? 6 : 36))
    let expectedMips = texture.name == "diffuse" ? 0...0 : 0...5
    let expected = Set(expectedMips.flatMap { mip in (0..<6).map { "\(mip):\($0)" } })
    let actual = texture.levels.map { "\($0.mip):\($0.face)" }
    precondition(Set(actual) == expected && Set(actual).count == actual.count)
    var hasLight = false
    for level in texture.levels {
        precondition(level.data.count == level.width * level.height * 8)
        precondition(level.face >= 0 && level.face < 6 && level.mip >= 0 && level.mip <= 5)
        precondition(level.width == 256 >> level.mip && level.height == level.width)
        level.data.withUnsafeBytes { bytes in
            for component in 0..<(bytes.count / 2) {
                let bits = bytes.loadUnaligned(fromByteOffset: component * 2, as: UInt16.self)
                let value = Float16(bitPattern: UInt16(littleEndian: bits))
                precondition(value.isFinite, "Non-finite environment component")
                if component % 4 != 3 && value > 0 { hasLight = true }
            }
        }
    }
    precondition(hasLight, "Environment RGB is black")
}
let encoder = PropertyListEncoder()
encoder.outputFormat = .binary
let plist = try encoder.encode(bake)
let compressed = try (plist as NSData).compressed(using: .lzfse) as Data
try compressed.write(to: output, options: .atomic)
