import Foundation
import GLTFCore
import Metal

/// The page's exact filtered lighting, exported once by MetalEnvironmentBakeTests.
/// No WebKit, image decode, or shader source compilation takes place when using these assets.
final class MetalEnvironment {
    struct Bake: Codable {
        var version: Int
        var upstream: String
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
        var data: Data
    }
    let intensityScale: Float
    private let textures: [String: any MTLTexture]
    private let sampler: any MTLSamplerState

    /// The last environment loaded in this process, shared by every renderer on the same device:
    /// a new Quick Look or thumbnail host does not decompress and upload the bake again.
    /// One entry, so at most one environment outlives the renderers that use it.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: (device: UInt64, environment: KhronosEnvironments, value: MetalEnvironment)?

    static func shared(device: any MTLDevice, library: any MTLLibrary, queue: any MTLCommandQueue,
                       environment: KhronosEnvironments) throws -> MetalEnvironment {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cache, cache.device == device.registryID, cache.environment == environment { return cache.value }
        let value = try MetalEnvironment(device: device, library: library, queue: queue, environment: environment)
        cache = (device.registryID, environment, value)
        return value
    }

    init(device: any MTLDevice, library: any MTLLibrary, queue: any MTLCommandQueue, environment: KhronosEnvironments) throws {
        guard let hdr = environment.bundledURL else { throw MetalRendererError.resource("environment HDR") }
        let url = hdr.deletingPathExtension().appendingPathExtension("metalibl")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetalRendererError.resource("Missing baked Khronos IBL: \(url.lastPathComponent). Run MetalEnvironmentBakeTests with GLTF_METAL_BAKE=1.")
        }
        func decode(_ source: URL) throws -> Bake {
            let compressed = try Data(contentsOf: source)
            let bytes = try (compressed as NSData).decompressed(using: .lzfse) as Data
            return try PropertyListDecoder().decode(Bake.self, from: bytes)
        }
        let bake = try decode(url)
        let shared = try decode(url.deletingLastPathComponent().appendingPathComponent("shared.metalibl"))
        guard bake.version == 1, bake.upstream == "863b981", bake.intensityScale.isFinite else {
            throw MetalRendererError.resource("Unsupported Khronos IBL bake")
        }
        intensityScale = bake.intensityScale
        var made: [String: any MTLTexture] = [:]
        for source in bake.textures + shared.textures {
            guard let level0 = source.levels.first(where: { $0.mip == 0 }), level0.width > 0, level0.height > 0 else {
                throw MetalRendererError.resource("Invalid environment texture \(source.name)")
            }
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = source.cube ? .typeCube : .type2D
            descriptor.pixelFormat = .rgba16Float
            descriptor.width = level0.width
            descriptor.height = level0.height
            descriptor.mipmapLevelCount = (source.levels.map(\.mip).max() ?? 0) + 1
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw MetalRendererError.resource(source.name) }
            for level in source.levels {
                guard level.data.count == level.width * level.height * 8,
                      level.face >= 0, level.face < (source.cube ? 6 : 1) else {
                    throw MetalRendererError.resource("Invalid environment level \(source.name)")
                }
                level.data.withUnsafeBytes { bytes in
                    texture.replace(region: MTLRegionMake2D(0, 0, level.width, level.height), mipmapLevel: level.mip,
                                    slice: level.face, withBytes: bytes.baseAddress!, bytesPerRow: level.width * 8,
                                    bytesPerImage: level.width * level.height * 8)
                }
            }
            made[source.name] = texture
        }
        for name in ["diffuse", "specular", "sheen", "ggxLUT", "charlieLUT", "sheenELUT"] {
            guard made[name] != nil else { throw MetalRendererError.resource("Missing IBL \(name)") }
        }
        textures = made
        let sampling = MTLSamplerDescriptor()
        sampling.minFilter = .linear
        sampling.magFilter = .linear
        sampling.mipFilter = .linear
        sampling.sAddressMode = .clampToEdge
        sampling.tAddressMode = .clampToEdge
        sampling.rAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: sampling) else { throw MetalRendererError.resource("IBL sampler") }
        self.sampler = sampler
    }

    func bind(_ encoder: any MTLRenderCommandEncoder) {
        for (index, name) in ["diffuse", "specular", "ggxLUT", "sheen", "charlieLUT", "sheenELUT"].enumerated() {
            encoder.setFragmentTexture(textures[name], index: index + 5)
        }
        encoder.setFragmentSamplerState(sampler, index: 5)
    }
}
