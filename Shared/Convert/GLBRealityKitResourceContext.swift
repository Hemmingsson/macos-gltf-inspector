import Accelerate
import GLTFKit2
import RealityKit

class GLBRealityKitResourceContext {
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

    var defaultMaterial: any Material {
        return RealityKit.SimpleMaterial(color: .init(white: 0.5, alpha: 1.0), isMetallic: false)
    }

    init() {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Unable to create Metal system default device")
        }
        self.device = metalDevice
        self.commandQueue = metalDevice.makeCommandQueue()!
    }

    @MainActor func alphaUsage(for gltfTextureParams: GLTFTextureParams) -> GLBTextureAlpha.Usage {
        let gltfTexture = gltfTextureParams.texture
        guard let image = (gltfTexture.basisUSource ?? gltfTexture.webpSource ?? gltfTexture.source) else {
            return .unused
        }
        var cgImage = cgImagesForImageIdentifiers[image.identifier]
        if cgImage == nil {
            cgImage = image.newCGImage()?.takeRetainedValue()
            if let cgImage {
                cgImagesForImageIdentifiers[image.identifier] = cgImage
            }
        }
        guard let cgImage, let range = GLBTextureAlpha.range(of: cgImage) else { return .unused }
        return GLBTextureAlpha.usage(minAlpha: range.0, maxAlpha: range.1)
    }

    @MainActor func cachedCGImage(for gltfTextureParams: GLTFTextureParams) -> CGImage? {
        let gltfTexture = gltfTextureParams.texture
        guard let image = (gltfTexture.basisUSource ?? gltfTexture.webpSource ?? gltfTexture.source) else {
            return nil
        }
        if let existing = cgImagesForImageIdentifiers[image.identifier] {
            return existing
        }
        let cgImage = image.newCGImage()?.takeRetainedValue()
        if let cgImage {
            cgImagesForImageIdentifiers[image.identifier] = cgImage
        }
        return cgImage
    }

    @MainActor func opacityTexture(for gltfTextureParams: GLTFTextureParams)
        -> RealityKit.PhysicallyBasedMaterial.Texture?
    {
        guard let cgImage = cachedCGImage(for: gltfTextureParams),
              let gray = GLBTextureAlpha.opacityMap(of: cgImage)
        else { return nil }
        let options = TextureResource.CreateOptions(semantic: .raw)
        guard let resource = try? TextureResource.generate(from: gray, options: options) else { return nil }
        let descriptor = MTLSamplerDescriptor(from: gltfTextureParams.texture.sampler ?? GLTFTextureSampler())
        return RealityKit.PhysicallyBasedMaterial.Texture(
            resource,
            sampler: MaterialParameters.Texture.Sampler(descriptor)
        )
    }

    @MainActor func texture(for gltfTextureParams: GLTFTextureParams, channels: ColorMask,
                            semantic: RealityKit.TextureResource.Semantic) -> RealityKit.PhysicallyBasedMaterial.Texture?
    {
        let gltfTexture = gltfTextureParams.texture
        guard let image = (gltfTexture.basisUSource ?? gltfTexture.webpSource ?? gltfTexture.source) else { return nil }
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
                    if textureResourcesForImageIdentifiers[gltfImage.identifier] != nil {
                        textureResourcesForImageIdentifiers[gltfImage.identifier]!.append((resource, channels))
                    } else {
                        textureResourcesForImageIdentifiers[gltfImage.identifier] = [(resource, channels)]
                    }
                    return resource
                } catch {
                    GLBLog.error(GLBLog.load, "KTX2 texture convert failed: \(error)")
                    return nil
                }
        }

        var cgImage = cgImagesForImageIdentifiers[gltfImage.identifier]
        if cgImage == nil {
            cgImage = gltfImage.newCGImage()?.takeRetainedValue()
            if cgImage != nil {
                cgImagesForImageIdentifiers[gltfImage.identifier] = cgImage
            }
        }
        guard let originalImage = cgImage else { return nil }

        guard let sourceImage = (channels == .all) ? originalImage :
                singleChannelImage(from: originalImage, channels: channels) else { return nil }

        let options = TextureResource.CreateOptions(semantic: semantic)
        guard let resource = try? TextureResource.generate(from: sourceImage, options: options) else { return nil }
        if textureResourcesForImageIdentifiers[gltfImage.identifier] != nil {
            textureResourcesForImageIdentifiers[gltfImage.identifier]!.append((resource, channels))
        } else {
            textureResourcesForImageIdentifiers[gltfImage.identifier] = [(resource, channels)]
        }

        return resource
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
