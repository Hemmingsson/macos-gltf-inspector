import CoreGraphics
import Foundation
import GLTFKit2
import ImageIO
import Metal

/// Raster images preserve the encoded RGB numbers (no conversion to the display colour profile).
/// The temporary premultiplied bitmap is converted back to straight alpha before GPU upload.
///
/// Each image is decoded once (`decode`); its linear and sRGB textures are both made from those
/// bytes (`makeTexture`), and one command buffer generates every texture's mips (`generateMipmaps`).
enum MetalImageLoader {
    /// Straight-alpha RGBA8 rows, or a finished KTX2 texture (which keeps its own transfer function).
    enum Decoded {
        case pixels(Data, width: Int, height: Int, bytesPerRow: Int)
        case texture(any MTLTexture)
    }

    static func decode(image: GLTFImage, device: any MTLDevice) throws -> Decoded {
        if image.inferMediaType() == GLTFMediaTypeKTX2 { return .texture(try loadKTX2(image: image, device: device)) }
        guard let cg = image.newCGImage()?.takeRetainedValue() else { throw MetalSceneError.invalid("Image decoding failed") }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0,
              width <= MetalResourceLimits.maxImageDimension, height <= MetalResourceLimits.maxImageDimension else {
            throw MetalSceneError.invalid("Image dimensions are too large")
        }
        let pixelCount = try MetalResourceLimits.product(width, height, label: "Image pixel count",
                                                          limit: MetalResourceLimits.maxDecodedImageBytes / 4)
        let rgbaBytes = try MetalResourceLimits.product(pixelCount, 4, label: "Image allocation",
                                                         limit: MetalResourceLimits.maxDecodedImageBytes)
        let rowBytes = try MetalResourceLimits.product(width, 4, label: "Image row size")
        let sourceBytes = try MetalResourceLimits.product(cg.bytesPerRow, height, label: "Image source size",
                                                           limit: MetalResourceLimits.maxDecodedImageBytes)
        let alpha = cg.alphaInfo
        let order = cg.bitmapInfo.intersection(.byteOrderMask)
        let directRGBA = cg.bitsPerComponent == 8 && cg.bitsPerPixel == 32
            && (alpha == .last || alpha == .noneSkipLast)
            && (order == [] || order == .byteOrder32Big)
        let directRGB = cg.bitsPerComponent == 8 && cg.bitsPerPixel == 24 && alpha == .none
        if (directRGBA || directRGB), let provider = cg.dataProvider, let data = provider.data,
           CFDataGetLength(data) >= sourceBytes, let bytes = CFDataGetBytePtr(data) {
            // ImageIO's straight component provider avoids an 8-bit premultiply/unpremultiply
            // roundtrip, preserving RGB values in semitransparent texels exactly.
            if directRGBA && alpha == .last {
                // Already straight RGBA8: upload ImageIO's rows as they are.
                return .pixels(data as Data, width: width, height: height, bytesPerRow: cg.bytesPerRow)
            }
            var pixels = Data(count: rgbaBytes)
            let expanded = pixels.withUnsafeMutableBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return false }
                GLTFMetalExpandRGBA8(bytes, cg.bytesPerRow, directRGBA ? 4 : 3, false, width, height,
                                     base.assumingMemoryBound(to: UInt8.self))
                return true
            }
            guard expanded else { throw MetalSceneError.invalid("Image bitmap allocation failed") }
            return .pixels(pixels, width: width, height: height, bytesPerRow: width * 4)
        }
        // Less common grayscale/16-bit encodings use a bitmap with a device colour tag;
        // changing the tag before drawing prevents an ICC display-profile conversion.
        let sourceSpace = cg.colorSpace?.model == .monochrome ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let untagged = cg.copy(colorSpace: sourceSpace) ?? cg
        var pixels = Data(count: rgbaBytes)
        let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: rowBytes,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(untagged,in:CGRect(x:0,y:0,width:width,height:height))
            GLTFMetalUnpremultiplyRGBA8(base.assumingMemoryBound(to: UInt8.self), pixelCount)
            return true
        }
        guard ok else { throw MetalSceneError.invalid("Image bitmap allocation failed") }
        return .pixels(pixels, width: width, height: height, bytesPerRow: width * 4)
    }

    /// Level 0 of a mipmapped RGBA8 texture; its mips come from `generateMipmaps`. sRGB colour mips
    /// must be filtered through the sRGB format (as WebGL does), so sRGB is its own texture.
    static func makeTexture(_ decoded: Decoded, device: any MTLDevice, sRGB: Bool) throws -> any MTLTexture {
        guard case let .pixels(pixels, width, height, bytesPerRow) = decoded else {
            if case let .texture(texture) = decoded { return texture }
            throw MetalSceneError.invalid("Unreachable image state")
        }
        guard width > 0, height > 0, width <= MetalResourceLimits.maxImageDimension,
              height <= MetalResourceLimits.maxImageDimension,
              bytesPerRow >= 0,
              pixels.count <= MetalResourceLimits.maxDecodedImageBytes else {
            throw MetalSceneError.invalid("Image dimensions or data are too large")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:sRGB ? .rgba8Unorm_srgb : .rgba8Unorm,width:width,height:height,mipmapped:true)
        descriptor.storageMode = .shared; descriptor.usage = [.shaderRead,.pixelFormatView]
        guard let texture = device.makeTexture(descriptor:descriptor) else { throw MetalSceneError.invalid("Metal texture allocation failed") }
        let uploaded = pixels.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: base, bytesPerRow: bytesPerRow)
            return true
        }
        guard uploaded else { throw MetalSceneError.invalid("Image data is empty") }
        return texture
    }

    /// Fills every mip chain in one command buffer on a queue shared by all loads on the device.
    static func generateMipmaps(_ textures: [any MTLTexture], device: any MTLDevice) throws {
        guard !textures.isEmpty else { return }
        guard let queue = queue(for: device), let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw MetalSceneError.invalid("Metal mip generation failed")
        }
        command.label = "Scene texture mips"
        for texture in textures { blit.generateMipmaps(for: texture) }
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
    }

    private static let queueLock = NSLock()
    nonisolated(unsafe) private static var queues: [UInt64: any MTLCommandQueue] = [:]
    private static func queue(for device: any MTLDevice) -> (any MTLCommandQueue)? {
        queueLock.lock(); defer { queueLock.unlock() }
        if let queue = queues[device.registryID] { return queue }
        let queue = device.makeCommandQueue()
        queue?.label = "Scene loader"
        queues[device.registryID] = queue
        return queue
    }

    /// The viewer uploads KTX2 through libktx's glUpload: Basis payloads become ASTC 4x4 and the
    /// file's transfer function (not the material slot) selects sRGB decoding.
    private static func loadKTX2(image: GLTFImage, device: any MTLDevice) throws -> any MTLTexture {
        let data = try encodedData(image)
        let ktx: OpaquePointer? = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return nil }
            return GLTFMetalKTX2Create(base.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        guard let ktx else {
            throw MetalSceneError.invalid("KTX2 texture decoding failed")
        }
        defer { GLTFMetalKTX2Destroy(ktx) }
        let sRGB = GLTFMetalKTX2IsSRGB(ktx)
        let format: MTLPixelFormat
        switch GLTFMetalKTX2VkFormat(ktx) {
        case 157, 158: format = sRGB ? .astc_4x4_srgb : .astc_4x4_ldr
        case 37, 43: format = sRGB ? .rgba8Unorm_srgb : .rgba8Unorm
        case 145, 146: format = sRGB ? .bc7_rgbaUnorm_srgb : .bc7_rgbaUnorm
        default: throw MetalSceneError.invalid("Unsupported KTX2 format \(GLTFMetalKTX2VkFormat(ktx))")
        }
        let width = Int(GLTFMetalKTX2Width(ktx)), height = Int(GLTFMetalKTX2Height(ktx))
        let levels = Int(GLTFMetalKTX2LevelCount(ktx))
        guard width > 0, height > 0, width <= MetalResourceLimits.maxImageDimension,
              height <= MetalResourceLimits.maxImageDimension, levels > 0, levels <= 16 else {
            throw MetalSceneError.invalid("KTX2 dimensions or mip levels are invalid")
        }
        var mipPixels = 0
        for level in 0..<levels {
            let levelWidth = max(1, width >> level), levelHeight = max(1, height >> level)
            let levelPixels = try MetalResourceLimits.product(levelWidth, levelHeight, label: "KTX2 level size")
            mipPixels = try MetalResourceLimits.sum(mipPixels, levelPixels, label: "KTX2 mip size")
        }
        _ = try MetalResourceLimits.product(mipPixels, 4, label: "KTX2 image size",
                                            limit: MetalResourceLimits.maxDecodedImageBytes)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: levels > 1)
        descriptor.mipmapLevelCount = levels
        descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .pixelFormatView]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw MetalSceneError.invalid("Metal texture allocation failed") }
        for level in 0..<levels {
            var bytesPerRow = 0, bytesPerImage = 0
            guard let bytes = GLTFMetalKTX2Level(ktx, UInt32(level), &bytesPerRow, &bytesPerImage) else {
                throw MetalSceneError.invalid("KTX2 level \(level) is missing")
            }
            let region = MTLRegionMake2D(0, 0, max(1, width >> level), max(1, height >> level))
            guard bytesPerRow > 0, bytesPerImage >= bytesPerRow else {
                throw MetalSceneError.invalid("KTX2 level \(level) has invalid row bytes")
            }
            texture.replace(region: region, mipmapLevel: level, slice: 0, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        }
        return texture
    }

    private static func encodedData(_ image: GLTFImage) throws -> Data {
        if let view = image.bufferView, let buffer = view.buffer.data {
            let length = Int(view.length)
            let end = try MetalResourceLimits.sum(view.offset, length, label: "Image bufferView range")
            guard view.offset >= 0, end <= buffer.count else { throw MetalSceneError.invalid("Image bufferView is out of range") }
            guard length <= MetalResourceLimits.maxSingleAllocationBytes else {
                throw MetalSceneError.invalid("Image data is too large")
            }
            return buffer.subdata(in: view.offset..<end)
        }
        guard let uri = image.uri else { throw MetalSceneError.invalid("Image has no data") }
        if uri.scheme == "data" {
            let text = uri.absoluteString
            guard let comma = text.firstIndex(of: ","), let data = Data(base64Encoded: String(text[text.index(after: comma)...])) else {
                throw MetalSceneError.invalid("Unsupported image data URI")
            }
            guard data.count <= MetalResourceLimits.maxSingleAllocationBytes else {
                throw MetalSceneError.invalid("Image data is too large")
            }
            return data
        }
        let scoped = image.assetDirectoryURL?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { image.assetDirectoryURL?.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: uri, options: .mappedIfSafe)
        guard data.count <= MetalResourceLimits.maxSingleAllocationBytes else {
            throw MetalSceneError.invalid("Image data is too large")
        }
        return data
    }
}
