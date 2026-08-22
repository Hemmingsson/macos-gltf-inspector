import Accelerate
import GLTFKit2
import Metal
import RealityKit

private enum TextureFilter {
    static func minMip(from filter: GLTFMinMipFilter) -> (MTLSamplerMinMagFilter, MTLSamplerMipFilter) {
        switch filter {
        case .linear:
            return (.linear, .notMipmapped)
        case .nearest:
            return (.nearest, .notMipmapped)
        case .nearestNearest:
            return (.nearest, .nearest)
        case .linearNearest:
            return (.linear, .nearest)
        case .nearestLinear:
            return (.nearest, .linear)
        default:
            return (.linear, .linear)
        }
    }

    static func mag(from filter: GLTFMagFilter) -> MTLSamplerMinMagFilter {
        switch filter {
        case .nearest:
            return .nearest
        default:
            return .linear
        }
    }

    static func addressMode(from addressMode: GLTFAddressMode) -> MTLSamplerAddressMode {
        switch addressMode {
        case .repeat:
            return .repeat
        case .mirroredRepeat:
            return .mirrorRepeat
        default:
            return .clampToEdge
        }
    }
}

extension MTLSamplerDescriptor {
    convenience init(from sampler: GLTFTextureSampler) {
        self.init()
        normalizedCoordinates = true
        let (minFilter, mipFilter) = TextureFilter.minMip(from: sampler.minMipFilter)
        self.minFilter = minFilter
        self.mipFilter = mipFilter
        magFilter = TextureFilter.mag(from: sampler.magFilter)
        sAddressMode = TextureFilter.addressMode(from: sampler.wrapS)
        tAddressMode = TextureFilter.addressMode(from: sampler.wrapT)
    }
}

class RealityKitResourceContext {
    enum ColorMask : Int {
        case red
        case green
        case blue
        case alpha
        case all

        var textureSwizzle: MTLTextureSwizzleChannels {
            switch self {
            case .red:
                return MTLTextureSwizzleChannels(red: .red, green: .red, blue: .red, alpha: .alpha)
            case .green:
                return MTLTextureSwizzleChannels(red: .green, green: .green, blue: .green, alpha: .alpha)
            case .blue:
                return MTLTextureSwizzleChannels(red: .blue, green: .blue, blue: .blue, alpha: .alpha)
            case .alpha:
                return MTLTextureSwizzleChannels(red: .alpha, green: .alpha, blue: .alpha, alpha: .alpha)
            case .all:
                return MTLTextureSwizzleChannels(red: .red, green: .green, blue: .blue, alpha: .alpha)
            }
        }
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var cgImagesForImageIdentifiers = [UUID : CGImage]()
    private var textureResourcesForImageIdentifiers = [UUID : [(RealityKit.TextureResource, ColorMask)]]()
    private var convertedMaterialsForIdentifiers = [ObjectIdentifier: any Material]()

    var problems = ConvertProblemReport()

    var defaultMaterial: any Material {
        return RealityKit.SimpleMaterial(color: .init(white: 0.5, alpha: 1.0), isMetallic: false)
    }

    func record(
        _ code: ConvertProblem.Code,
        severity: ConvertProblem.Severity,
        message: String,
        materialName: String? = nil
    ) {
        problems.append(code, severity: severity, message: message, materialName: materialName)
    }

    /// Bind a referenced glTF texture; nil after a reference is a convert error.
    @MainActor func requiredTexture(
        for gltfTextureParams: GLTFTextureParams,
        channels: ColorMask,
        semantic: RealityKit.TextureResource.Semantic,
        materialName: String?
    ) -> RealityKit.PhysicallyBasedMaterial.Texture? {
        if let bound = texture(for: gltfTextureParams, channels: channels, semantic: semantic) {
            return bound
        }
        record(
            .missingTexture,
            severity: .error,
            message: "Texture did not load",
            materialName: materialName
        )
        return nil
    }

    @MainActor func cachedConvertedMaterial(for gltfMaterial: GLTFMaterial) -> (any Material)? {
        convertedMaterialsForIdentifiers[ObjectIdentifier(gltfMaterial)]
    }

    @MainActor func storeConvertedMaterial(_ material: any Material, for gltfMaterial: GLTFMaterial) {
        convertedMaterialsForIdentifiers[ObjectIdentifier(gltfMaterial)] = material
    }

    init() {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Unable to create Metal system default device")
        }
        self.device = metalDevice
        self.commandQueue = metalDevice.makeCommandQueue()!
    }

    @MainActor func alphaUsage(for gltfTextureParams: GLTFTextureParams) -> TextureAlpha.Usage {
        guard let image = RealityKitResourceContext.gltfImage(for: gltfTextureParams.texture),
              let cgImage = cachedCGImage(for: image),
              let range = TextureAlpha.range(of: cgImage)
        else { return .unused }
        return TextureAlpha.usage(minAlpha: range.0, maxAlpha: range.1)
    }

    @MainActor func texture(for gltfTextureParams: GLTFTextureParams, channels: ColorMask,
                            semantic: RealityKit.TextureResource.Semantic) -> RealityKit.PhysicallyBasedMaterial.Texture?
    {
        let gltfTexture = gltfTextureParams.texture
        guard let image = RealityKitResourceContext.gltfImage(for: gltfTexture) else { return nil }
        if let resource = textureResource(for:image, channels: channels, semantic: semantic) {
            let descriptor = MTLSamplerDescriptor(from: gltfTexture.sampler ?? GLTFTextureSampler())
            let sampler = MaterialParameters.Texture.Sampler(descriptor)
            return RealityKit.PhysicallyBasedMaterial.Texture(resource, sampler: sampler)
        }
        return nil
    }

    @MainActor func textureResource(for gltfImage: GLTFImage, channels: ColorMask,
                                    semantic: RealityKit.TextureResource.Semantic) -> RealityKit.TextureResource?
    {
        let existingResources = textureResourcesForImageIdentifiers[gltfImage.identifier]
        if let existingMatch = existingResources?.first(where: { $0.1 == channels })?.0 {
            return existingMatch
        }

        if gltfImage.inferMediaType() == GLTFMediaTypeKTX2 {
            let mtlTexture = gltfImage.newTexture(with: device)
            guard let sourceTexture = mtlTexture else { return nil }
            do {
                let lowLevelDesc = LowLevelTexture.Descriptor(textureType: sourceTexture.textureType,
                                                              pixelFormat: sourceTexture.pixelFormat,
                                                              width: sourceTexture.width,
                                                              height: sourceTexture.height,
                                                              depth: sourceTexture.depth,
                                                              mipmapLevelCount: sourceTexture.mipmapLevelCount,
                                                              arrayLength: sourceTexture.arrayLength,
                                                              textureUsage: [.shaderRead],
                                                              swizzle: channels.textureSwizzle)
                let lowLevelTexture = try LowLevelTexture(descriptor: lowLevelDesc)
                if let commandBuffer = commandQueue.makeCommandBuffer() {
                    let targetTexture = lowLevelTexture.replace(using: commandBuffer)
                    if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                        blitEncoder.copy(from: sourceTexture, to: targetTexture)
                        blitEncoder.endEncoding()
                    }
                    commandBuffer.commit()
                }
                let resource = try TextureResource(from: lowLevelTexture)
                storeTextureResource(resource, for: gltfImage, channels: channels)
                return resource
            } catch {
                AppLog.error(AppLog.load, "KTX2 texture convert failed: \(error)")
                return nil
            }
        }

        guard let originalImage = cachedCGImage(for: gltfImage) else { return nil }

        guard let sourceImage = (channels == .all) ? originalImage :
                singleChannelImage(from: originalImage, channels: channels) else { return nil }

        let options = TextureResource.CreateOptions(semantic: semantic)
        guard let resource = try? TextureResource(image: sourceImage, withName: nil, options: options) else { return nil }
        storeTextureResource(resource, for: gltfImage, channels: channels)
        return resource

    }

    static func gltfImage(for texture: GLTFTexture) -> GLTFImage? {
        texture.basisUSource ?? texture.webpSource ?? texture.source
    }

    /// Reuse convert-time decode cache for inspector thumbs (no second `newCGImage` when warm).
    @MainActor func cgImage(for gltfImage: GLTFImage) -> CGImage? {
        cachedCGImage(for: gltfImage)
    }

    @MainActor private func cachedCGImage(for gltfImage: GLTFImage) -> CGImage? {
        if let existing = cgImagesForImageIdentifiers[gltfImage.identifier] {
            return existing
        }
        let cgImage = gltfImage.newCGImage()?.takeRetainedValue()
        if let cgImage {
            cgImagesForImageIdentifiers[gltfImage.identifier] = cgImage
        }
        return cgImage
    }

    private func storeTextureResource(
        _ resource: RealityKit.TextureResource,
        for gltfImage: GLTFImage,
        channels: ColorMask
    ) {
        textureResourcesForImageIdentifiers[gltfImage.identifier, default: []].append((resource, channels))
    }

    func singleChannelImage(from cgImage: CGImage, channels: ColorMask) -> CGImage? {
        guard (cgImage.colorSpace?.model == .rgb) else {
            // Can't extract from a non-RGB[A] image with this method. Fall back to the input image hoping it's monochrome.
            return cgImage
        }
        // PNG on macOS is usually BGRA. `vImageExtractChannel_ARGB8888` only
        // matches after we convert; RealityKit then samples the gray as red.
        guard let argbFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
            renderingIntent: .defaultIntent
        ) else { return nil }
        guard var inputBuffer = try? vImage_Buffer(cgImage: cgImage, format: argbFormat) else { return nil }
        defer { inputBuffer.free() }
        var outputBuffer = vImage_Buffer()
        vImageBuffer_Init(&outputBuffer, inputBuffer.height, inputBuffer.width, 8, vImage_Flags())
        defer { outputBuffer.data.deallocate() }
        // ARGB8888: 0=A, 1=R, 2=G, 3=B
        let channel: Int
        switch channels {
        case .red: channel = 1
        case .green: channel = 2
        case .blue: channel = 3
        case .alpha: channel = 0
        case .all: return nil
        }
        let outputColorSpace = CGColorSpace(name: CGColorSpace.linearGray)!
        let outputFormat = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 8, colorSpace: outputColorSpace,
                                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                                renderingIntent: .defaultIntent)!
        vImageExtractChannel_ARGB8888(&inputBuffer, &outputBuffer, channel, vImage_Flags())
        let outputImage = try? outputBuffer.createCGImage(format: outputFormat)
        return outputImage
    }
}
