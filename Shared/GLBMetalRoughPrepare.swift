import CoreGraphics
import Foundation
import ImageIO
import simd
import UniformTypeIdentifiers

/// Rewrites `KHR_materials_pbrSpecularGlossiness` to metal/rough + specular/IOR,
/// matching `@gltf-transform/functions` `metalRough()`.
enum GLBMetalRoughPrepare {
    private static let specGlossName = "KHR_materials_pbrSpecularGlossiness"
    private static let specularName = "KHR_materials_specular"
    private static let iorName = "KHR_materials_ior"
    private static let maxBakeEdge = 1024

    static func preparedURL(from url: URL) throws -> URL {
        let json = try GLBBox.peekJSON(from: url)
        guard needsConversion(json) else { return url }
        let data = try Data(contentsOf: url)
        let converted = try convert(try GLBBox.parse(data))
        return try GLBBox.writePrepared(converted, prefix: "glb-metalrough")
    }

    static func needsConversion(_ json: [String: Any]) -> Bool {
        guard let materials = json["materials"] as? [[String: Any]] else { return false }
        return materials.contains { material in
            ((material["extensions"] as? [String: Any])?[specGlossName]) != nil
        }
    }

    private static func convert(_ glb: GLBBox) throws -> Data {
        var json = glb.json
        var bin = glb.bin
        var images = json["images"] as? [[String: Any]] ?? []
        var bufferViews = json["bufferViews"] as? [[String: Any]] ?? []
        var materials = json["materials"] as? [[String: Any]] ?? []

        let bakeTextures = shouldBakeTextures(json: json, materials: materials)

        func addPNGTexture(_ png: Data) -> Int {
            let bufferView = GLBBox.appendBytes(png, bin: &bin, bufferViews: &bufferViews)
            images.append(["mimeType": "image/png", "bufferView": bufferView])
            return appendTexture(&json, imageIndex: images.count - 1)
        }

        for i in materials.indices {
            guard var extensions = materials[i]["extensions"] as? [String: Any],
                  let specGloss = extensions[specGlossName] as? [String: Any]
            else { continue }

            let diffuseFactor = doubleArray(specGloss["diffuseFactor"], fallback: [1, 1, 1, 1])
            let specularFactor = doubleArray(specGloss["specularFactor"], fallback: [1, 1, 1])
            let glossinessFactor = doubleValue(specGloss["glossinessFactor"], fallback: 1)

            var pbr = materials[i]["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            pbr["baseColorFactor"] = [1.0, 1.0, 1.0, diffuseFactor.count > 3 ? diffuseFactor[3] : 1.0]
            pbr["metallicFactor"] = 1.0
            pbr["roughnessFactor"] = 1.0
            if let diffuseTexture = specGloss["diffuseTexture"] {
                pbr["baseColorTexture"] = diffuseTexture
            }

            var specular: [String: Any] = [
                "specularFactor": 1.0,
                "specularColorFactor": specularFactor,
            ]

            if bakeTextures,
               let sgInfo = specGloss["specularGlossinessTexture"] as? [String: Any],
               let sgImageIndex = textureImageIndex(json: json, textureInfo: sgInfo)
            {
                let sgPixels = try decodeImage(glb: glb, images: images, imageIndex: sgImageIndex).downsampled(maxEdge: maxBakeEdge)
                var diffusePixels: PixelImage?
                if let diffuseInfo = specGloss["diffuseTexture"] as? [String: Any],
                   let diffuseIndex = textureImageIndex(json: json, textureInfo: diffuseInfo)
                {
                    diffusePixels = try decodeImage(glb: glb, images: images, imageIndex: diffuseIndex).downsampled(maxEdge: maxBakeEdge)
                }
                let baked = bakeWorkflow(
                    diffuse: diffusePixels,
                    specGloss: sgPixels,
                    diffuseFactor: diffuseFactor,
                    specularFactor: specularFactor,
                    glossinessFactor: glossinessFactor
                )
                let specularPNG = try encodePNG(rewriteSpecular(sgPixels))
                let basePNG = try encodePNG(baked.baseColor)
                let metalRoughPNG = try encodePNG(baked.metalRough)

                let specularTex = addPNGTexture(specularPNG)
                let baseTex = addPNGTexture(basePNG)
                let metalRoughTex = addPNGTexture(metalRoughPNG)

                var specTex = sgInfo
                specTex["index"] = specularTex
                specular["specularTexture"] = specTex
                specular["specularColorTexture"] = specTex

                var baseInfo = (specGloss["diffuseTexture"] as? [String: Any]) ?? sgInfo
                baseInfo["index"] = baseTex
                pbr["baseColorTexture"] = baseInfo

                var mrTex = sgInfo
                mrTex["index"] = metalRoughTex
                pbr["metallicRoughnessTexture"] = mrTex
            } else {
                let converted = metalRoughFrom(
                    diffuse: rgb(diffuseFactor),
                    specular: rgb(specularFactor),
                    glossiness: glossinessFactor
                )
                pbr["baseColorFactor"] = [converted.base.x, converted.base.y, converted.base.z, diffuseFactor.count > 3 ? diffuseFactor[3] : 1]
                pbr["metallicFactor"] = converted.metallic
                pbr["roughnessFactor"] = converted.roughness
            }

            materials[i]["pbrMetallicRoughness"] = pbr
            extensions.removeValue(forKey: specGlossName)
            extensions[specularName] = specular
            extensions[iorName] = ["ior": 1000.0]
            materials[i]["extensions"] = extensions
        }

        json["materials"] = materials
        json["images"] = images
        json["bufferViews"] = bufferViews
        GLBBox.setPrimaryBufferLength(&json, bin.count)

        GLBBox.rewriteExtensionLists(
            &json,
            removing: [specGlossName],
            addingToUsed: [specularName, iorName]
        )
        return try GLBBox.serialize(json: json, bin: bin)
    }

    static func shouldBakeTextures(json: [String: Any], materials: [[String: Any]]) -> Bool {
        let images = (json["images"] as? [[String: Any]])?.count ?? 0
        if images > 40 { return false }
        var textured = 0
        for material in materials {
            let specGloss = (material["extensions"] as? [String: Any])?[specGlossName] as? [String: Any]
            if specGloss?["specularGlossinessTexture"] != nil {
                textured += 1
            }
        }
        return textured <= 24
    }

    private static func textureImageIndex(json: [String: Any], textureInfo: [String: Any]) -> Int? {
        guard let index = GLBBox.intValue(textureInfo["index"]),
              let textures = json["textures"] as? [[String: Any]],
              textures.indices.contains(index)
        else { return nil }
        return GLBBox.intValue(textures[index]["source"])
    }

    private static func doubleValue(_ value: Any?, fallback: Double) -> Double {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        default: return fallback
        }
    }

    private static func doubleArray(_ value: Any?, fallback: [Double]) -> [Double] {
        guard let items = value as? [Any] else { return fallback }
        return items.map { doubleValue($0, fallback: 0) }
    }

    private static func appendTexture(_ json: inout [String: Any], imageIndex: Int) -> Int {
        var textures = json["textures"] as? [[String: Any]] ?? []
        textures.append(["source": imageIndex])
        json["textures"] = textures
        return textures.count - 1
    }

    private static func decodeImage(glb: GLBBox, images: [[String: Any]], imageIndex: Int) throws -> PixelImage {
        guard images.indices.contains(imageIndex),
              let viewIndex = GLBBox.intValue(images[imageIndex]["bufferView"]),
              let views = glb.json["bufferViews"] as? [[String: Any]],
              views.indices.contains(viewIndex)
        else {
            throw PrepareError.missingImage
        }
        let view = views[viewIndex]
        let offset = GLBBox.intValue(view["byteOffset"]) ?? 0
        let length = GLBBox.intValue(view["byteLength"]) ?? 0
        guard offset >= 0, length >= 0, offset + length <= glb.bin.count else {
            throw PrepareError.missingImage
        }
        let slice = glb.bin.subdata(in: offset..<(offset + length))
        guard let source = CGImageSourceCreateWithData(slice as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw PrepareError.decodeImage
        }
        return try PixelImage(cgImage: cgImage)
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

    private static func encodePNG(_ image: PixelImage) throws -> Data {
        guard let destData = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(destData, UTType.png.identifier as CFString, 1, nil)
        else {
            throw PrepareError.encodeImage
        }
        CGImageDestinationAddImage(dest, try image.makeCGImage(), nil)
        guard CGImageDestinationFinalize(dest) else { throw PrepareError.encodeImage }
        return destData as Data
    }

    enum PrepareError: Error {
        case missingImage
        case decodeImage
        case encodeImage
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
            throw GLBMetalRoughPrepare.PrepareError.decodeImage
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
            throw GLBMetalRoughPrepare.PrepareError.encodeImage
        }
        return image
    }
}
