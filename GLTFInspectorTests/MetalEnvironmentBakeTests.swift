import Foundation
import GLTFCore
import Testing
@testable import RendererWebKit

/// Explicit generator for the native port's exact pinned Khronos lighting. It exports the page's
/// GPU-filtered textures in binary property lists. Never runs during normal tests.
@MainActor
struct MetalEnvironmentBakeTests {
    struct Bake: Codable {
        var version = 1
        var upstream = "863b981"
        var environment: String
        var intensityScale: Float
        var mipCount: Int
        var textures: [Texture]
    }
    struct Texture: Codable {
        var name: String
        var size: Int
        var cube: Bool
        var levels: [Level]
    }
    struct Level: Codable {
        var mip: Int
        var face: Int
        var width: Int
        var height: Int
        /// Little-endian IEEE 754 half floats, RGBA, in upstream readPixels row order.
        var data: Data
    }
    struct Metadata: Decodable {
        struct Texture: Decodable {
            var name: String
            var size: Int
            var cube: Bool
            var mipLevels: Int
        }
        var intensityScale: Float
        var mipCount: Int
        var textures: [Texture]
    }
    struct Readback: Decodable {
        var width: Int
        var height: Int
        var data: Data
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLTF_METAL_BAKE"] == "1",
        "GLTF_METAL_BAKE=1 ./scripts/dev.sh test -only-testing:GLTFInspectorTests/MetalEnvironmentBakeTests"))
    func bakePinnedEnvironments() async throws {
        for environment in KhronosEnvironments.allCases {
            let host = try WebRendererHost(mode: .still, size: 64, timeout: .seconds(180))
            try await host.start()
            var look = RenderLook.standard
            look.environment = environment
            try await host.apply(WebPreviewCanvas.Look(render: look))
            let metadata: Metadata = try await host.call("exportEnvironment", ["metadata": true])
            var textures: [Texture] = []
            for texture in metadata.textures {
                var levels: [Level] = []
                for mip in 0..<texture.mipLevels {
                    for face in 0..<(texture.cube ? 6 : 1) {
                        struct Request: Encodable { var name: String; var mip: Int; var face: Int }
                        let readback: Readback = try await host.call("exportEnvironment", Request(
                            name: texture.name, mip: mip, face: face
                        ))
                        let expectedByteCount = readback.width * readback.height * 4 * MemoryLayout<Float>.size
                        try #require(readback.data.count == expectedByteCount)
                        var half = Data(capacity: expectedByteCount / 2)
                        readback.data.withUnsafeBytes { raw in
                            for offset in stride(from: 0, to: raw.count, by: 4) {
                                let bits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                                var converted = Float16(Float(bitPattern: bits)).bitPattern.littleEndian
                                withUnsafeBytes(of: &converted) { half.append(contentsOf: $0) }
                            }
                        }
                        levels.append(Level(mip: mip, face: face, width: readback.width,
                                            height: readback.height, data: half))
                    }
                }
                textures.append(Texture(name: texture.name, size: texture.size, cube: texture.cube, levels: levels))
                print("baked \(environment.rawValue) \(texture.name): \(levels.count) subresources")
            }
            let bake = Bake(environment: environment.rawValue, intensityScale: metadata.intensityScale,
                            mipCount: metadata.mipCount, textures: textures)
            let output = TestFixtures.url("assets/ibl/khronos/\(environment.rawValue).metalibl")
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            var lighting = bake
            lighting.textures = bake.textures.filter { !$0.name.hasSuffix("LUT") }
            let compressed = try (encoder.encode(lighting) as NSData).compressed(using: .lzfse)
            try (compressed as Data).write(to: output, options: .atomic)
            if environment == KhronosEnvironments.allCases.first {
                var shared = bake
                shared.environment = "shared"
                shared.textures = bake.textures.filter { $0.name.hasSuffix("LUT") }
                let luts = try (encoder.encode(shared) as NSData).compressed(using: .lzfse)
                try (luts as Data).write(to: output.deletingLastPathComponent().appendingPathComponent("shared.metalibl"), options: .atomic)
            }
            print("baked \(output.path)")
        }
    }
}
