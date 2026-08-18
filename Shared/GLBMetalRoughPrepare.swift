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

    static func preparedURL(from url: URL) throws -> URL {
        GLBLog.event(GLBLog.prepare, "preparedURL start \(GLBLog.describeURL(url))")
        let json = try GLBBox.peekJSON(from: url)
        let materials = (json["materials"] as? [[String: Any]])?.count ?? 0
        let images = (json["images"] as? [[String: Any]])?.count ?? 0
        let extensionsUsed = (json["extensionsUsed"] as? [String]) ?? []
        GLBLog.event(
            GLBLog.prepare,
            "peeked json jsonKeys=\(json.keys.sorted()) materials=\(materials) images=\(images) extensionsUsed=\(extensionsUsed)"
        )
        guard needsConversion(json) else {
            GLBLog.event(GLBLog.prepare, "no spec/gloss conversion needed")
            return url
        }
        GLBLog.event(GLBLog.prepare, "converting spec/gloss → metal/rough")
        let data = try Data(contentsOf: url)
        let glb = try GLBBox.parse(data)
        let converted = try GLBLog.timed(GLBLog.prepare, "specGloss convert") {
            try convert(glb)
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-metalrough-\(UUID().uuidString).glb")
        try converted.write(to: out)
        GLBLog.event(GLBLog.prepare, "wrote rewritten glb bytes=\(converted.count) path=\(out.path)")
        return out
    }

    private static func needsConversion(_ json: [String: Any]) -> Bool {
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

            if let sgInfo = specGloss["specularGlossinessTexture"] as? [String: Any],
               let sgImageIndex = textureImageIndex(json: json, textureInfo: sgInfo)
            {
                let sgPixels = try decodeImage(glb: glb, images: images, imageIndex: sgImageIndex)
                var diffusePixels: PixelImage?
                if let diffuseInfo = specGloss["diffuseTexture"] as? [String: Any],
                   let diffuseIndex = textureImageIndex(json: json, textureInfo: diffuseInfo)
                {
                    diffusePixels = try decodeImage(glb: glb, images: images, imageIndex: diffuseIndex)
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

                let specularBV = appendImage(&bin, &bufferViews, png: specularPNG)
                images.append(["mimeType": "image/png", "bufferView": specularBV])
                let specularTex = appendTexture(&json, imageIndex: images.count - 1)
                let baseBV = appendImage(&bin, &bufferViews, png: basePNG)
                images.append(["mimeType": "image/png", "bufferView": baseBV])
                let baseTex = appendTexture(&json, imageIndex: images.count - 1)
                let metalRoughBV = appendImage(&bin, &bufferViews, png: metalRoughPNG)
                images.append(["mimeType": "image/png", "bufferView": metalRoughBV])
                let metalRoughTex = appendTexture(&json, imageIndex: images.count - 1)

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
        if var buffers = json["buffers"] as? [[String: Any]], !buffers.isEmpty {
            buffers[0]["byteLength"] = bin.count
            json["buffers"] = buffers
        }

        rewriteExtensionLists(&json)
        return try GLBBox.serialize(json: json, bin: bin)
    }

    private static func textureImageIndex(json: [String: Any], textureInfo: [String: Any]) -> Int? {
        guard let index = intValue(textureInfo["index"]),
              let textures = json["textures"] as? [[String: Any]],
              textures.indices.contains(index)
        else { return nil }
        return intValue(textures[index]["source"])
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let n as Int: return n
        case let n as NSNumber: return n.intValue
        default: return nil
        }
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

    private static func appendImage(_ bin: inout Data, _ bufferViews: inout [[String: Any]], png: Data) -> Int {
        let offset = glbAligned(bin.count, 4)
        if offset > bin.count {
            bin.append(Data(count: offset - bin.count))
        }
        bin.append(png)
        bufferViews.append([
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": png.count,
        ])
        return bufferViews.count - 1
    }

    private static func rewriteExtensionLists(_ json: inout [String: Any]) {
        func rewrite(_ key: String, adding: [String]) {
            var list = (json[key] as? [String]) ?? []
            list.removeAll { $0 == specGlossName }
            for name in adding where !list.contains(name) {
                list.append(name)
            }
            if list.isEmpty {
                json.removeValue(forKey: key)
            } else {
                json[key] = list
            }
        }
        rewrite("extensionsUsed", adding: [specularName, iorName])
        rewrite("extensionsRequired", adding: [])
    }

    private static func decodeImage(glb: GLBBox, images: [[String: Any]], imageIndex: Int) throws -> PixelImage {
        guard images.indices.contains(imageIndex),
              let viewIndex = intValue(images[imageIndex]["bufferView"]),
              let views = glb.json["bufferViews"] as? [[String: Any]],
              views.indices.contains(viewIndex)
        else {
            throw PrepareError.missingImage
        }
        let view = views[viewIndex]
        let offset = intValue(view["byteOffset"]) ?? 0
        let length = intValue(view["byteLength"]) ?? 0
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
        case invalidGLB
    }
}

private func glbAligned(_ value: Int, _ align: Int) -> Int {
    (value + align - 1) / align * align
}

private struct GLBBox {
    private static let magic = Data("glTF".utf8)

    var json: [String: Any]
    var bin: Data

    static func parse(_ data: Data) throws -> GLBBox {
        guard data.count >= 12, data.prefix(4) == magic else {
            throw GLBMetalRoughPrepare.PrepareError.invalidGLB
        }
        var offset = 12
        var json: [String: Any] = [:]
        var bin = Data()
        while offset + 8 <= data.count {
            let chunkLen = Int(readUInt32(data, offset))
            let type = String(data: data.subdata(in: (offset + 4)..<(offset + 8)), encoding: .ascii) ?? ""
            let start = offset + 8
            let end = start + chunkLen
            guard end <= data.count else { throw GLBMetalRoughPrepare.PrepareError.invalidGLB }
            let payload = data.subdata(in: start..<end)
            if type.hasPrefix("JSON") {
                json = try jsonObject(from: payload)
            } else if type.hasPrefix("BIN") {
                bin = payload
            }
            offset = glbAligned(end, 4)
        }
        return GLBBox(json: json, bin: bin)
    }

    /// JSON chunk only — skips the BIN so metal/rough files are not fully copied just to
    /// decide that spec/gloss conversion is unnecessary. First chunk is JSON per the GLB spec.
    static func peekJSON(from url: URL) throws -> [String: Any] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 12), header.count == 12, header.prefix(4) == magic,
              let chunkHeader = try handle.read(upToCount: 8), chunkHeader.count == 8
        else {
            throw GLBMetalRoughPrepare.PrepareError.invalidGLB
        }
        let chunkLen = Int(readUInt32(chunkHeader, 0))
        let type = String(data: chunkHeader.subdata(in: 4..<8), encoding: .ascii) ?? ""
        guard type.hasPrefix("JSON"),
              let payload = try handle.read(upToCount: chunkLen), payload.count == chunkLen
        else {
            throw GLBMetalRoughPrepare.PrepareError.invalidGLB
        }
        return try jsonObject(from: payload)
    }

    static func serialize(json: [String: Any], bin: Data) throws -> Data {
        var jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
        jsonData.append(Data(repeating: 0x20, count: pad4(jsonData.count)))
        var binData = bin
        binData.append(Data(count: pad4(binData.count)))

        var out = Data()
        out.append(contentsOf: Array("glTF".utf8))
        out.append(contentsOf: uint32(2))
        let total = 12 + 8 + jsonData.count + 8 + binData.count
        out.append(contentsOf: uint32(UInt32(total)))
        out.append(contentsOf: uint32(UInt32(jsonData.count)))
        out.append(contentsOf: Array("JSON".utf8))
        out.append(jsonData)
        out.append(contentsOf: uint32(UInt32(binData.count)))
        out.append(contentsOf: Array("BIN\0".utf8))
        out.append(binData)
        return out
    }

    private static func jsonObject(from payload: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw GLBMetalRoughPrepare.PrepareError.invalidGLB
        }
        return object
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    private static func uint32(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }

    private static func pad4(_ count: Int) -> Int {
        (4 - (count % 4)) % 4
    }
}

private struct PixelImage {
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
