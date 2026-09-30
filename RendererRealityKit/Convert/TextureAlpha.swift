import CoreGraphics
import Foundation

enum TextureAlpha {
    enum Usage: Equatable {
        /// Missing, constant 0 (Sketchfab empty), or constant 1.
        case unused
        /// Billboard / decal foliage — keep cutout, do not force opaque.
        case cutout
    }

    static func usage(minAlpha: Float, maxAlpha: Float, spanLimit: Float = 0.15) -> Usage {
        (maxAlpha - minAlpha) < spanLimit ? .unused : .cutout
    }

    static func range(of image: CGImage) -> (Float, Float)? {
        let info = image.alphaInfo
        switch info {
        case .none, .noneSkipLast, .noneSkipFirst:
            return (1, 1)
        default:
            break
        }
        let width = min(image.width, 64)
        let height = min(image.height, 64)
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minA: UInt8 = 255
        var maxA: UInt8 = 0
        for i in stride(from: 3, to: pixels.count, by: 4) {
            minA = min(minA, pixels[i])
            maxA = max(maxA, pixels[i])
        }
        return (Float(minA) / 255, Float(maxA) / 255)
    }
}
