import GLTFCore
import GLTFKit2
import Metal
import os
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
    /// One upload per (image, semantic); single channels are read with `Texture.swizzle`.
    private var textureResourcesForImageIdentifiers = [UUID : [(RealityKit.TextureResource, RealityKit.TextureResource.Semantic)]]()
    private var convertedMaterialsForIdentifiers = [ObjectIdentifier: any Material]()

    var problems = ConvertProblemReport()
    /// Image decode and `TextureResource` upload time so far (non-KTX images), for `ConvertTimings`.
    private(set) var textureDecodeTime: Duration = .zero
    private(set) var textureUploadTime: Duration = .zero
    /// Longest texture edge to upload; larger rasters are downscaled after decode. Finder icons
    /// only (`RealityThumbnail`): a 512 px icon cannot show 4K texels, and `TextureResource`
    /// generation on large rasters is the measured residual load cost.
    var maxImageEdge: Int?

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

    /// Whole-image texture for `channels == .all`; otherwise the same upload read through a
    /// swizzle (data channels use `.raw`, so no colour conversion touches them; alpha is linear in
    /// every semantic, so an opacity read reuses whatever upload the image already has).
    @MainActor func texture(for gltfTextureParams: GLTFTextureParams, channels: ColorMask,
                            semantic: RealityKit.TextureResource.Semantic) -> RealityKit.PhysicallyBasedMaterial.Texture?
    {
        let gltfTexture = gltfTextureParams.texture
        guard let image = RealityKitResourceContext.gltfImage(for: gltfTexture) else { return nil }
        let resourceSemantic: RealityKit.TextureResource.Semantic = channels == .all ? semantic : .raw
        let reuse = channels == .alpha ? textureResourcesForImageIdentifiers[image.identifier]?.first?.0 : nil
        guard let resource = reuse ?? textureResource(for: image, semantic: resourceSemantic) else { return nil }
        let descriptor = MTLSamplerDescriptor(from: gltfTexture.sampler ?? GLTFTextureSampler())
        var texture = RealityKit.PhysicallyBasedMaterial.Texture(resource, sampler: MaterialParameters.Texture.Sampler(descriptor))
        if channels != .all {
            texture.swizzle = channels.textureSwizzle
        }
        texture.uvIndex = TextureTransforms.uvSet(of: gltfTextureParams)
        return texture
    }

    @MainActor func textureResource(for gltfImage: GLTFImage,
                                    semantic: RealityKit.TextureResource.Semantic) -> RealityKit.TextureResource?
    {
        if let existing = textureResourcesForImageIdentifiers[gltfImage.identifier]?.first(where: { $0.1 == semantic })?.0 {
            return existing
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
                                                              textureUsage: [.shaderRead])
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
                storeTextureResource(resource, for: gltfImage, semantic: semantic)
                return resource
            } catch {
                AppLog.error(AppLog.load, "KTX2 texture convert failed: \(error)")
                return nil
            }
        }

        guard let image = cachedCGImage(for: gltfImage) else { return nil }
        let options = TextureResource.CreateOptions(semantic: semantic)
        let uploadStart = ContinuousClock.now
        let upload = AppLog.signposter.withIntervalSignpost("texture.upload") {
            try? TextureResource(image: image, withName: nil, options: options)
        }
        textureUploadTime += .now - uploadStart
        guard let resource = upload else { return nil }
        storeTextureResource(resource, for: gltfImage, semantic: semantic)
        return resource
    }

    static func gltfImage(for texture: GLTFTexture) -> GLTFImage? {
        texture.basisUSource ?? texture.webpSource ?? texture.source
    }

    @MainActor private func cachedCGImage(for gltfImage: GLTFImage) -> CGImage? {
        if let existing = cgImagesForImageIdentifiers[gltfImage.identifier] {
            return existing
        }
        let decodeStart = ContinuousClock.now
        let cgImage = AppLog.signposter.withIntervalSignpost("texture.decode") {
            (gltfImage.newCGImage()?.takeRetainedValue()).map(capped)
        }
        textureDecodeTime += .now - decodeStart
        if let cgImage {
            cgImagesForImageIdentifiers[gltfImage.identifier] = cgImage
        }
        return cgImage
    }

    private func capped(_ image: CGImage) -> CGImage {
        guard let maxImageEdge, max(image.width, image.height) > maxImageEdge else { return image }
        let scale = Double(maxImageEdge) / Double(max(image.width, image.height))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private func storeTextureResource(
        _ resource: RealityKit.TextureResource,
        for gltfImage: GLTFImage,
        semantic: RealityKit.TextureResource.Semantic
    ) {
        textureResourcesForImageIdentifiers[gltfImage.identifier, default: []].append((resource, semantic))
    }
}
