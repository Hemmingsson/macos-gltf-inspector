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
        let sharedURL = url.deletingLastPathComponent().appendingPathComponent("shared.metalibl")
        // Each bake is decompressed, uploaded, and released before the next. The decoded
        // level `Data` is a second copy of the pixels; drop it as soon as the GPU texture has it.
        let loaded = try Self.upload(device: device, lighting: url, shared: sharedURL)
        intensityScale = loaded.scale
        let made = loaded.textures
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

    /// Decompress one `.metalibl` at a time and release its plist bytes before returning.
    private static func upload(device: any MTLDevice, lighting: URL, shared: URL) throws -> (scale: Float, textures: [String: any MTLTexture]) {
        var made: [String: any MTLTexture] = [:]
        let scale: Float = try autoreleasepool {
            var bake = try decode(lighting)
            guard bake.version == 1, bake.upstream == "863b981", bake.intensityScale.isFinite else {
                throw MetalRendererError.resource("Unsupported Khronos IBL bake")
            }
            try upload(bake: &bake, device: device, into: &made)
            return bake.intensityScale
        }
        try autoreleasepool {
            var bake = try decode(shared)
            try upload(bake: &bake, device: device, into: &made)
        }
        return (scale, made)
    }

    private static func decode(_ source: URL) throws -> Bake {
        let compressed = try Data(contentsOf: source)
        let bytes = try (compressed as NSData).decompressed(using: .lzfse) as Data
        return try PropertyListDecoder().decode(Bake.self, from: bytes)
    }

    private static func upload(bake: inout Bake, device: any MTLDevice, into made: inout [String: any MTLTexture]) throws {
        for index in bake.textures.indices {
            let name = bake.textures[index].name
            let cube = bake.textures[index].cube
            let header = bake.textures[index].levels.first { $0.mip == 0 }.map { (width: $0.width, height: $0.height) }
            guard let header, header.width > 0, header.height > 0 else {
                throw MetalRendererError.resource("Invalid environment texture \(name)")
            }
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = cube ? .typeCube : .type2D
            descriptor.pixelFormat = .rgba16Float
            descriptor.width = header.width
            descriptor.height = header.height
            descriptor.mipmapLevelCount = (bake.textures[index].levels.map(\.mip).max() ?? 0) + 1
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw MetalRendererError.resource(name) }
            for levelIndex in bake.textures[index].levels.indices {
                let level = bake.textures[index].levels[levelIndex]
                guard level.data.count == level.width * level.height * 8,
                      level.face >= 0, level.face < (cube ? 6 : 1) else {
                    throw MetalRendererError.resource("Invalid environment level \(name)")
                }
                level.data.withUnsafeBytes { bytes in
                    texture.replace(region: MTLRegionMake2D(0, 0, level.width, level.height), mipmapLevel: level.mip,
                                    slice: level.face, withBytes: bytes.baseAddress!, bytesPerRow: level.width * 8,
                                    bytesPerImage: level.width * level.height * 8)
                }
                bake.textures[index].levels[levelIndex].data = Data()
            }
            bake.textures[index].levels = []
            made[name] = texture
        }
    }

    func bind(_ encoder: any MTLRenderCommandEncoder) {
        for (index, name) in ["diffuse", "specular", "ggxLUT", "sheen", "charlieLUT", "sheenELUT"].enumerated() {
            encoder.setFragmentTexture(textures[name], index: index + 5)
        }
        encoder.setFragmentSamplerState(sampler, index: 5)
    }
}
