import CoreGraphics
import Foundation
import GLTFKit2
import ImageIO
import Metal

/// Raster images preserve the encoded RGB numbers (no conversion to the display colour profile).
/// The temporary premultiplied bitmap is converted back to straight alpha before GPU upload.
enum MetalImageLoader {
    static func load(image: GLTFImage, device: any MTLDevice, sRGB: Bool) throws -> any MTLTexture {
        if image.inferMediaType() == GLTFMediaTypeKTX2 { return try loadKTX2(image: image, device: device) }
        guard let cg = image.newCGImage()?.takeRetainedValue() else { throw MetalSceneError.invalid("Image decoding failed") }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { throw MetalSceneError.invalid("Image dimensions are empty") }
        var pixels = [UInt8](repeating:0,count:width*height*4)
        let alpha = cg.alphaInfo
        let order = cg.bitmapInfo.intersection(.byteOrderMask)
        let directRGBA = cg.bitsPerComponent == 8 && cg.bitsPerPixel == 32
            && (alpha == .last || alpha == .noneSkipLast)
            && (order == [] || order == .byteOrder32Big)
        let directRGB = cg.bitsPerComponent == 8 && cg.bitsPerPixel == 24 && alpha == .none
        if (directRGBA || directRGB), let provider = cg.dataProvider, let data = provider.data,
           CFDataGetLength(data) >= cg.bytesPerRow * height, let bytes = CFDataGetBytePtr(data) {
            // ImageIO's straight component provider avoids an 8-bit premultiply/unpremultiply
            // roundtrip, preserving RGB values in semitransparent texels exactly.
            let components = directRGBA ? 4 : 3
            for y in 0..<height {
                for x in 0..<width {
                    let src = y * cg.bytesPerRow + x * components
                    let dst = (y * width + x) * 4
                    pixels[dst] = bytes[src]; pixels[dst+1] = bytes[src+1]; pixels[dst+2] = bytes[src+2]
                    pixels[dst+3] = directRGBA && alpha == .last ? bytes[src+3] : 255
                }
            }
        } else {
            // Less common grayscale/16-bit encodings use a bitmap with a device colour tag;
            // changing the tag before drawing prevents an ICC display-profile conversion.
            let sourceSpace = cg.colorSpace?.model == .monochrome ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let untagged = cg.copy(colorSpace: sourceSpace) ?? cg
            let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data:raw.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                context.interpolationQuality = .none
                context.draw(untagged,in:CGRect(x:0,y:0,width:width,height:height))
                return true
            }
            guard ok else { throw MetalSceneError.invalid("Image bitmap allocation failed") }
            for i in stride(from:0,to:pixels.count,by:4) {
                let a = Int(pixels[i+3])
                if a > 0 && a < 255 {
                    for c in 0..<3 {
                        let value = (Int(pixels[i+c]) * 255 + a/2) / a
                        pixels[i+c] = UInt8(min(255, value))
                    }
                }
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:sRGB ? .rgba8Unorm_srgb : .rgba8Unorm,width:width,height:height,mipmapped:true)
        descriptor.storageMode = .shared; descriptor.usage = [.shaderRead,.pixelFormatView]
        guard let texture = device.makeTexture(descriptor:descriptor) else { throw MetalSceneError.invalid("Metal texture allocation failed") }
        pixels.withUnsafeBytes { raw in texture.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:raw.baseAddress!,bytesPerRow:width*4) }
        guard let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else { throw MetalSceneError.invalid("Metal mip generation failed") }
        blit.generateMipmaps(for:texture); blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        return texture
    }

    /// The page uploads KTX2 through libktx's glUpload: Basis payloads become ASTC 4x4 and the
    /// file's transfer function (not the material slot) selects sRGB decoding.
    private static func loadKTX2(image: GLTFImage, device: any MTLDevice) throws -> any MTLTexture {
        let data = try encodedData(image)
        guard let ktx = data.withUnsafeBytes({ GLTFMetalKTX2Create($0.baseAddress, $0.count) }) else {
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
            texture.replace(region: region, mipmapLevel: level, slice: 0, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        }
        return texture
    }

    private static func encodedData(_ image: GLTFImage) throws -> Data {
        if let view = image.bufferView, let buffer = view.buffer.data {
            guard view.offset >= 0, view.offset + Int(view.length) <= buffer.count else { throw MetalSceneError.invalid("Image bufferView is out of range") }
            return buffer.subdata(in: view.offset..<view.offset + Int(view.length))
        }
        guard let uri = image.uri else { throw MetalSceneError.invalid("Image has no data") }
        if uri.scheme == "data" {
            let text = uri.absoluteString
            guard let comma = text.firstIndex(of: ","), let data = Data(base64Encoded: String(text[text.index(after: comma)...])) else {
                throw MetalSceneError.invalid("Unsupported image data URI")
            }
            return data
        }
        let scoped = image.assetDirectoryURL?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { image.assetDirectoryURL?.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: uri, options: .mappedIfSafe)
    }
}
