import CoreGraphics
import Foundation
import GLTFCore
import GLTFKit2
import simd

/// `KHR_materials_pbrSpecularGlossiness` → metal/rough + `KHR_materials_specular`, matching
/// `@gltf-transform/functions` `metalRough()`. Runs on the parsed `GLTFAsset` before convert,
/// off the main actor: each spec-gloss `GLTFMaterial` is rewritten in place, and baked maps
/// become in-memory `GLTFImage(cgImage:)` textures (no GLB rewrite, no PNG round trip).
/// RealityKit cannot invert glossiness (no `1 − x` swizzle), so textured materials are baked.
enum SpecGlossBake {
    private static let maxBakeEdge = 1024

    struct Result: Equatable {
        var converted = false
        var baked = false
    }

    enum BakeError: Error {
        case decode
        case encode
    }

    static func apply(to asset: GLTFAsset) -> Result {
        let materials = asset.materials.filter { $0.specularGlossiness != nil }
        guard !materials.isEmpty else { return Result() }
        let bakeTextures = RealityPolicy.bakesSpecGlossTextures(
            imageCount: asset.images.count,
            texturedMaterialCount: materials.filter { $0.specularGlossiness?.specularGlossinessTexture != nil }.count
        )
        var result = Result(converted: true)
        for material in materials where convert(material, bakeTextures: bakeTextures) {
            result.baked = true
        }
        return result
    }

    /// Rewrites one material; `true` when its textures were baked.
    private static func convert(_ material: GLTFMaterial, bakeTextures: Bool) -> Bool {
        guard let specGloss = material.specularGlossiness else { return false }
        let d = specGloss.diffuseFactor
        let diffuseFactor = [Double(d.x), Double(d.y), Double(d.z), Double(d.w)]
        let s = specGloss.specularFactor
        let specularFactor = [Double(s.x), Double(s.y), Double(s.z)]
        let glossinessFactor = Double(specGloss.glossinessFactor)

        let pbr = GLTFPBRMetallicRoughnessParams()
        pbr.baseColorFactor = [1, 1, 1, d.w]
        pbr.metallicFactor = 1
        pbr.roughnessFactor = 1
        pbr.baseColorTexture = specGloss.diffuseTexture
        let specular = GLTFSpecularParams()
        specular.specularFactor = 1
        specular.specularColorFactor = s

        var baked = false
        if bakeTextures, let sgInfo = specGloss.specularGlossinessTexture {
            do {
                let sgPixels = try pixels(sgInfo).downsampled(maxEdge: maxBakeEdge)
                let diffusePixels = try specGloss.diffuseTexture.map { try pixels($0).downsampled(maxEdge: maxBakeEdge) }
                let out = bakeWorkflow(
                    diffuse: diffusePixels,
                    specGloss: sgPixels,
                    diffuseFactor: diffuseFactor,
                    specularFactor: specularFactor,
                    glossinessFactor: glossinessFactor
                )
                let specularTexture = try textureParams(like: sgInfo, image: rewriteSpecular(sgPixels))
                specular.specularTexture = specularTexture
                specular.specularColorTexture = specularTexture
                pbr.baseColorTexture = try textureParams(like: specGloss.diffuseTexture ?? sgInfo, image: out.baseColor)
                pbr.metallicRoughnessTexture = try textureParams(like: sgInfo, image: out.metalRough)
                baked = true
            } catch {
                AppLog.error(AppLog.load, "spec-gloss bake failed, using factors: \(error)")
            }
        }
        if !baked {
            let converted = metalRoughFrom(
                diffuse: rgb(diffuseFactor),
                specular: rgb(specularFactor),
                glossiness: glossinessFactor
            )
            pbr.baseColorFactor = [Float(converted.base.x), Float(converted.base.y), Float(converted.base.z), d.w]
            pbr.metallicFactor = Float(converted.metallic)
            pbr.roughnessFactor = Float(converted.roughness)
        }
        material.metallicRoughness = pbr
        material.specular = specular
        material.indexOfRefraction = 1000
        material.specularGlossiness = nil
        return baked
    }

    private static func pixels(_ params: GLTFTextureParams) throws -> PixelImage {
        guard let image = RealityKitResourceContext.gltfImage(for: params.texture),
              let cgImage = image.newCGImage()?.takeRetainedValue()
        else { throw BakeError.decode }
        return try PixelImage(cgImage: cgImage)
    }

    /// Same UV set / transform as `like`, a new texture over the baked image, default sampler.
    private static func textureParams(like source: GLTFTextureParams, image: PixelImage) throws -> GLTFTextureParams {
        let params = GLTFTextureParams()
        params.texture = GLTFTexture(source: GLTFImage(cgImage: try image.makeCGImage()))
        params.texCoord = source.texCoord
        params.transform = source.transform
        params.extensions = source.extensions
        return params
    }

    private static func rgb(_ values: [Double]) -> SIMD3<Double> {
        SIMD3(values.indices.contains(0) ? values[0] : 1,
              values.indices.contains(1) ? values[1] : 1,
              values.indices.contains(2) ? values[2] : 1)
    }

    private static func metalRoughFrom(
        diffuse: SIMD3<Double>,
        specular: SIMD3<Double>,
        glossiness: Double
    ) -> (base: SIMD3<Double>, metallic: Double, roughness: Double) {
        let f0 = 0.04
        let epsilon = 1e-6
        let oneMinusSpecularStrength = 1 - max(specular.x, max(specular.y, specular.z))
        let diffuseY = 0.2126 * diffuse.x + 0.7152 * diffuse.y + 0.0722 * diffuse.z
        let specularY = 0.2126 * specular.x + 0.7152 * specular.y + 0.0722 * specular.z
        let metallic: Double
        if specularY < f0 {
            metallic = 0
        } else {
            let a = f0
            let b = diffuseY * oneMinusSpecularStrength / (1 - f0) + specularY - 2 * f0
            let c = f0 - specularY
            let d = b * b - 4 * a * c
            metallic = min(1, max(0, (-b + sqrt(max(0, d))) / (2 * a)))
        }
        let fromDiffuse = diffuse * (oneMinusSpecularStrength / (1 - f0) / max(1 - metallic, epsilon))
        let fromSpecular = specular - SIMD3(repeating: f0) * (1 - metallic) * (1 / max(metallic, epsilon))
        let t = metallic * metallic
        let base = fromDiffuse * (1 - t) + fromSpecular * t
        return (
            SIMD3(min(1, max(0, base.x)), min(1, max(0, base.y)), min(1, max(0, base.z))),
            metallic,
            1 - glossiness
        )
    }

    private static func bakeWorkflow(
        diffuse: PixelImage?,
        specGloss: PixelImage,
        diffuseFactor: [Double],
        specularFactor: [Double],
        glossinessFactor: Double
    ) -> (baseColor: PixelImage, metalRough: PixelImage) {
        let width = specGloss.width
        let height = specGloss.height
        var base = PixelImage(width: width, height: height, bytes: [UInt8](repeating: 0, count: width * height * 4))
        var metalRough = base
        let dFactor = rgb(diffuseFactor)
        let sFactor = rgb(specularFactor)
        let alphaFactor = diffuseFactor.indices.contains(3) ? diffuseFactor[3] : 1
        for y in 0..<height {
            for x in 0..<width {
                let sg = specGloss.pixel(x: x, y: y)
                var albedo = dFactor
                var alpha = alphaFactor
                if let diffuse {
                    let u = x * diffuse.width / max(width, 1)
                    let v = y * diffuse.height / max(height, 1)
                    let dp = diffuse.pixel(x: u, y: v)
                    let a = max(dp.a, 1.0 / 255.0)
                    albedo *= SIMD3(dp.r / a, dp.g / a, dp.b / a)
                    alpha *= dp.a
                }
                var specular = sFactor
                let sa = max(sg.a, 1.0 / 255.0)
                specular *= SIMD3(sg.r / sa, sg.g / sa, sg.b / sa)
                let gloss = glossinessFactor * sg.a
                let converted = metalRoughFrom(diffuse: albedo, specular: specular, glossiness: gloss)
                base.setPixel(x: x, y: y, r: converted.base.x * alpha, g: converted.base.y * alpha, b: converted.base.z * alpha, a: alpha)
                metalRough.setPixel(x: x, y: y, r: 0, g: converted.roughness, b: converted.metallic, a: 1)
            }
        }
        return (base, metalRough)
    }

    private static func rewriteSpecular(_ image: PixelImage) -> PixelImage {
        var out = image
        for i in stride(from: 0, to: out.bytes.count, by: 4) {
            out.bytes[i + 3] = 255
        }
        return out
    }

}

struct PixelImage {
    var width: Int
    var height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func pixel(x: Int, y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let i = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
        return (
            Double(bytes[i]) / 255,
            Double(bytes[i + 1]) / 255,
            Double(bytes[i + 2]) / 255,
            Double(bytes[i + 3]) / 255
        )
    }

    mutating func setPixel(x: Int, y: Int, r: Double, g: Double, b: Double, a: Double) {
        let i = (y * width + x) * 4
        bytes[i] = UInt8(min(255, max(0, (r * 255).rounded())))
        bytes[i + 1] = UInt8(min(255, max(0, (g * 255).rounded())))
        bytes[i + 2] = UInt8(min(255, max(0, (b * 255).rounded())))
        bytes[i + 3] = UInt8(min(255, max(0, (a * 255).rounded())))
    }

    init(cgImage: CGImage) throws {
        width = cgImage.width
        height = cgImage.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SpecGlossBake.BakeError.decode
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func downsampled(maxEdge: Int) -> PixelImage {
        let longest = max(width, height)
        guard longest > maxEdge, longest > 0 else { return self }
        let scaledW = max(1, width * maxEdge / longest)
        let scaledH = max(1, height * maxEdge / longest)
        guard let source = try? makeCGImage() else { return self }
        var bytes = [UInt8](repeating: 0, count: scaledW * scaledH * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &bytes,
            width: scaledW,
            height: scaledH,
            bitsPerComponent: 8,
            bytesPerRow: scaledW * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }
        ctx.interpolationQuality = .medium
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: scaledW, height: scaledH))
        return PixelImage(width: scaledW, height: scaledH, bytes: bytes)
    }

    func makeCGImage() throws -> CGImage {
        var bytes = self.bytes
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = ctx.makeImage() else {
            throw SpecGlossBake.BakeError.encode
        }
        return image
    }
}
