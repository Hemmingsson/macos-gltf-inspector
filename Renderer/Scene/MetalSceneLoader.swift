import Foundation
import GLTFKit2
import Metal
import simd

public enum MetalSceneLoader {
    public static func load(url: URL, device: any MTLDevice, sceneIndex: Int? = nil, materialVariantIndex: Int? = nil) async throws -> MetalScene {
        try await Task.detached(priority: .userInitiated) {
            GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"
            let options: [GLTFAssetLoadingOption: Any] = [.assetDirectoryURLKey: url.deletingLastPathComponent()]
            let asset = try MetalMeshoptPreprocessor.decodedGLB(url: url).map { try GLTFAsset(data: $0, options: options) }
                ?? GLTFAsset(url: url, options: options)
            let builder = Builder(asset: asset, device: device, sourceURL: url)
            try await builder.prepareTextures()
            return try builder.build(sceneIndex: sceneIndex, materialVariantIndex: materialVariantIndex)
        }.value
    }
}

private final class Builder {
    let asset: GLTFAsset
    let device: any MTLDevice
    var materialCache: [ObjectIdentifier: MetalMaterial] = [:]
    /// Keyed by image identifier, with a `:srgb` suffix for the sRGB copy of a raster image.
    var textures: [String: any MTLTexture] = [:]
    /// Textures made after `prepareTextures`, whose mips `build` generates.
    var pendingMips: [any MTLTexture] = []
    var draws: [MetalDraw] = []
    var lights: [MetalPunctualLight] = []
    var minimum = SIMD3<Float>(repeating: .infinity)
    var maximum = SIMD3<Float>(repeating: -.infinity)
    var world: [ObjectIdentifier: simd_float4x4] = [:]
    let sourceURL: URL
    init(asset: GLTFAsset, device: any MTLDevice, sourceURL: URL) { self.asset = asset; self.device = device; self.sourceURL = sourceURL }
    /// The source file's JSON (GLB chunk or .gltf), for extension fields GLTFKit2 parses incorrectly.
    lazy var rawJSON: [String: Any]? = {
        guard let data = try? Data(contentsOf: sourceURL) else { return nil }
        var json = data
        if data.count >= 20, data.prefix(4) == Data("glTF".utf8) {
            let length = data.subdata(in: 12..<16).withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
            guard data.count >= 20 + length else { return nil }
            json = data.subdata(in: 20..<(20 + length))
        }
        return (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
    }()


    /// Decodes every image a material binds, in parallel and once each, then makes the linear
    /// and/or sRGB textures its slots need and generates all their mips in one command buffer.
    func prepareTextures() async throws {
        struct ImageJob: @unchecked Sendable { let image: GLTFImage; let linear: Bool; let sRGB: Bool; let device: any MTLDevice }
        struct Result: @unchecked Sendable { let key: String; let linear: (any MTLTexture)?; let sRGB: (any MTLTexture)?; let needsMips: Bool }
        var usage: [String: (image: GLTFImage, linear: Bool, sRGB: Bool)] = [:]
        for material in asset.materials {
            for (slot, params) in textureSlots(material) {
                guard let image = Self.image(of: params) else { continue }
                let key = image.identifier.uuidString
                var entry = usage[key] ?? (image, false, false)
                if Self.usesSRGBTexture(slot, image) { entry.sRGB = true } else { entry.linear = true }
                usage[key] = entry
            }
        }
        let jobs = usage.values.map { ImageJob(image: $0.image, linear: $0.linear, sRGB: $0.sRGB, device: device) }
        var mipmapped: [any MTLTexture] = []
        try await withThrowingTaskGroup(of: Result.self) { group in
            for job in jobs {
                group.addTask {
                    let decoded = try MetalImageLoader.decode(image: job.image, device: job.device)
                    let key = job.image.identifier.uuidString
                    if case let .texture(texture) = decoded { return Result(key: key, linear: texture, sRGB: nil, needsMips: false) }
                    return Result(key: key,
                                  linear: job.linear ? try MetalImageLoader.makeTexture(decoded, device: job.device, sRGB: false) : nil,
                                  sRGB: job.sRGB ? try MetalImageLoader.makeTexture(decoded, device: job.device, sRGB: true) : nil,
                                  needsMips: true)
                }
            }
            for try await result in group {
                if let linear = result.linear { textures[result.key] = linear }
                if let sRGB = result.sRGB { textures[result.key + ":srgb"] = sRGB }
                if result.needsMips { mipmapped += [result.linear, result.sRGB].compactMap { $0 } }
            }
        }
        try MetalImageLoader.generateMipmaps(mipmapped, device: device)
    }

    func build(sceneIndex: Int?, materialVariantIndex: Int?) throws -> MetalScene {
        let scene: GLTFScene?
        if let sceneIndex {
            guard asset.scenes.indices.contains(sceneIndex) else { throw MetalSceneError.invalid("Scene index is out of range") }
            scene = asset.scenes[sceneIndex]
        } else { scene = asset.defaultScene ?? asset.scenes.first }
        guard let scene else { throw MetalSceneError.invalid("The glTF has no scene") }
        let variant: GLTFMaterialVariant?
        if let materialVariantIndex, let variants = asset.materialVariants {
            guard variants.indices.contains(materialVariantIndex) else { throw MetalSceneError.invalid("Material variant index is out of range") }
            variant = variants[materialVariantIndex]
        } else { variant = nil }
        func collect(_ node: GLTFNode, _ parent: simd_float4x4) {
            let transform = parent * node.matrix
            world[ObjectIdentifier(node)] = transform
            for child in node.childNodes { collect(child, transform) }
        }
        for node in scene.nodes { collect(node, matrix_identity_float4x4) }
        // Joints may be outside the selected scene tree.
        func global(_ node: GLTFNode) -> simd_float4x4 {
            if let value = world[ObjectIdentifier(node)] { return value }
            let value = (node.parent.map { global($0) } ?? matrix_identity_float4x4) * node.matrix
            world[ObjectIdentifier(node)] = value
            return value
        }
        for skin in asset.skins { for joint in skin.joints { _ = global(joint) } }
        func visit(_ node: GLTFNode, visible: Bool) throws {
            let authoredVisibility = (node.extensions["KHR_node_visibility"] as? [String: Any])?["visible"] as? Bool ?? true
            guard visible && authoredVisibility else { return }
            let transform = world[ObjectIdentifier(node)] ?? matrix_identity_float4x4
            if let light = node.light {
                let p = transform * SIMD4<Float>(0, 0, 0, 1)
                let d = transform * SIMD4<Float>(0, 0, -1, 0)
                // Map GLTFKit2 light types (1...3) to the shader types (0...2).
                lights.append(MetalPunctualLight(type: Int(light.type.rawValue) - 1, position: SIMD3(p.x,p.y,p.z), direction: simd_normalize(SIMD3(d.x,d.y,d.z)), color: light.color, intensity: light.intensity, range: light.range, innerConeCos: cos(light.innerConeAngle), outerConeCos: cos(light.outerConeAngle)))
            }
            if let mesh = node.mesh {
                let instances = node.meshInstances
                for i in 0..<(instances?.instanceCount ?? 1) {
                    let model = transform * (instances?.transform(at: i) ?? matrix_identity_float4x4)
                    for primitive in mesh.primitives { try append(primitive, node: node, model: model, variant: variant) }
                }
            }
            for child in node.childNodes { try visit(child, visible: true) }
        }
        for node in scene.nodes { try visit(node, visible: true) }
        guard !draws.isEmpty else { throw MetalSceneError.invalid("The glTF scene contains no renderable primitives") }
        try MetalImageLoader.generateMipmaps(pendingMips, device: device)
        pendingMips.removeAll()
        return MetalScene(draws: draws, boundsMin: minimum, boundsMax: maximum, lights: lights, asset: asset)
    }

    func append(_ primitive: GLTFPrimitive, node: GLTFNode, model: simd_float4x4, variant: GLTFMaterialVariant?) throws {
        guard let accessor = primitive.attribute(forName: "POSITION")?.accessor else { throw MetalSceneError.invalid("Primitive has no POSITION accessor") }
        let count = accessor.count
        guard count > 0 else { return }
        let positions = try values(accessor, components: 3)
        func attribute(_ name: String, _ n: Int) throws -> [Float]? {
            guard let a = primitive.attribute(forName: name)?.accessor else { return nil }
            guard a.count == count else { throw MetalSceneError.invalid("Mismatched \(name) accessor count") }
            return try values(a, components: n)
        }
        let normal = try attribute("NORMAL", 3)
        let tangent = try attribute("TANGENT", 4)
        let uv0 = try attribute("TEXCOORD_0", 2)
        let uv1 = try attribute("TEXCOORD_1", 2)
        let colorAccessor = primitive.attribute(forName: "COLOR_0")?.accessor
        let colorComponents = colorAccessor?.dimension == .vector3 ? 3 : 4
        let color = try attribute("COLOR_0", colorComponents)
        var vertices = [MetalVertex](unsafeUninitializedCapacity: count) { buffer, initialized in
            GLTFMetalPackVertices(UnsafeMutableRawPointer(buffer.baseAddress!).assumingMemoryBound(to: Float.self), count,
                                  positions, normal, tangent, color, colorComponents, uv0, uv1)
            initialized = count
        }
        let weights = node.weights ?? node.mesh?.weights ?? []
        for (targetIndex, target) in primitive.targets.enumerated() where targetIndex < weights.count && weights[targetIndex].floatValue != 0 {
            let weight = weights[targetIndex].floatValue
            for attribute in target {
                let data = try values(attribute.accessor, components: 3)
                guard attribute.accessor.count == count else { throw MetalSceneError.invalid("Mismatched morph accessor count") }
                for i in 0..<count {
                    let delta = SIMD4<Float>(data[i*3],data[i*3+1],data[i*3+2],0) * weight
                    switch attribute.name {
                    case "POSITION": vertices[i].position += delta
                    case "NORMAL": vertices[i].normal += delta
                    case "TANGENT": vertices[i].tangent += delta
                    default: break
                    }
                }
            }
        }
        if let skin = node.skin, let joints = try attribute("JOINTS_0",4), let weights = try attribute("WEIGHTS_0",4) {
            let inverseBind: [Float]? = try skin.inverseBindMatrices.map { try values($0, components: 16) }
            let matrices = skin.joints.enumerated().map { i,joint -> simd_float4x4 in
                let ib: simd_float4x4
                if let b = inverseBind, b.count >= (i+1)*16 { ib = simd_float4x4(columns:(SIMD4(b[i*16],b[i*16+1],b[i*16+2],b[i*16+3]),SIMD4(b[i*16+4],b[i*16+5],b[i*16+6],b[i*16+7]),SIMD4(b[i*16+8],b[i*16+9],b[i*16+10],b[i*16+11]),SIMD4(b[i*16+12],b[i*16+13],b[i*16+14],b[i*16+15]))) } else { ib = matrix_identity_float4x4 }
                return simd_inverse(model) * (world[ObjectIdentifier(joint)] ?? matrix_identity_float4x4) * ib
            }
            for i in 0..<count {
                var blended = simd_float4x4(0)
                var total: Float = 0
                for c in 0..<4 {
                    let j = Int(joints[i*4+c]); let w = weights[i*4+c]
                    guard matrices.indices.contains(j) else { continue }
                    blended += matrices[j] * w; total += w
                }
                if total > 0 {
                    blended *= 1 / total
                    vertices[i].position = blended * vertices[i].position
                    let n = simd_transpose(simd_inverse(blended))
                    vertices[i].normal = n * vertices[i].normal
                    let sign = vertices[i].tangent.w
                    vertices[i].tangent.w = 0
                    vertices[i].tangent = blended * vertices[i].tangent
                    vertices[i].tangent.w = sign
                }
            }
        }
        var indices = try primitive.indices.map { try indexValues($0, vertexCount: count) } ?? Self.sequence(count)
        // Khronos Primitive.computeCentroid: Float32 accumulation over the authored indices and POSITIONs.
        var sum = SIMD3<Float>(repeating: 0)
        for index in indices { let i = Int(index) * 3; sum += SIMD3(positions[i], positions[i+1], positions[i+2]) }
        let centroid = SIMD3<Float>(sum.indices.map { Float(Double(sum[$0]) / Double(indices.count)) })
        // Khronos opaque instancing groups: skins, morph targets, GPU instancing and the
        // attribute limit (glAttributes + 4 > 16 on Apple WebGL2) each get their own group.
        let meshIndex = node.mesh.flatMap { mesh in asset.meshes.firstIndex { $0 === mesh } } ?? -1
        let primitiveIndex = node.mesh?.primitives.firstIndex { $0 === primitive } ?? -1
        let winding = simd_determinant(model) > 0 ? 1 : (simd_determinant(model) < 0 ? -1 : 0)
        var opaqueGroup = "\(meshIndex)_\(winding)_\(primitiveIndex)"
        if node.skin != nil || !primitive.targets.isEmpty || node.meshInstances != nil || primitive.attributes.count + 4 > 16 {
            opaqueGroup += "_node\(asset.nodes.firstIndex(of: node) ?? -1)"
        }
        let topology: MTLPrimitiveType
        switch primitive.primitiveType.rawValue - 1 {
        case 0: topology = .point
        case 1: topology = .line
        case 2:
            indices = indices.indices.flatMap { i in [indices[i], indices[(i+1)%indices.count]] }; topology = .line
        case 3: topology = .lineStrip
        case 4: topology = .triangle
        case 5:
            let source = indices
            indices = source.count < 3 ? [] : (2..<source.count).flatMap { i in i%2 == 0 ? [source[i-2],source[i-1],source[i]] : [source[i-1],source[i-2],source[i]] }; topology = .triangle
        case 6:
            let source = indices
            indices = source.count < 3 ? [] : (2..<source.count).flatMap { [source[0],source[$0-1],source[$0]] }; topology = .triangle
        default: throw MetalSceneError.invalid("Unsupported primitive topology")
        }
        if normal == nil && topology == .triangle {
            // Khronos generates a face normal when absent: split shared vertices to preserve hard edges.
            let flatCount = indices.count - indices.count%3
            vertices = Self.deindexed(vertices, indices, count: flatCount, faceNormals: true)
            indices = Self.sequence(flatCount)
        }
        if tangent == nil && uv0 != nil && topology == .triangle {
            // A tangent discontinuity can split one indexed vertex into several corners.
            // Keep Mikk's corner results by deindexing before running its callback interface.
            var corners = Self.deindexed(vertices, indices, count: indices.count, faceNormals: false)
            let cornerCount = corners.count
            let generated = corners.withUnsafeMutableBytes { raw in
                GLTFMetalGenerateTangents(raw.baseAddress, cornerCount)
            }
            guard generated else { throw MetalSceneError.invalid("MikkTSpace tangent generation failed") }
            vertices = corners
            indices = Self.sequence(corners.count)
        }
        guard !indices.isEmpty else { return }
        withUnsafeBytes(of: model) { matrix in
            withUnsafeMutableBytes(of: &minimum) { lo in
                withUnsafeMutableBytes(of: &maximum) { hi in
                    vertices.withUnsafeBytes { raw in
                        GLTFMetalBounds(raw.baseAddress?.assumingMemoryBound(to: Float.self), vertices.count,
                                        matrix.baseAddress!.assumingMemoryBound(to: Float.self),
                                        lo.baseAddress!.assumingMemoryBound(to: Float.self),
                                        hi.baseAddress!.assumingMemoryBound(to: Float.self))
                    }
                }
            }
        }
        guard let vb = device.makeBuffer(bytes: vertices, length: vertices.count*MemoryLayout<MetalVertex>.stride, options: .storageModeShared), let ib = device.makeBuffer(bytes:indices,length:indices.count*4,options:.storageModeShared) else { throw MetalSceneError.invalid("Metal buffer allocation failed") }
        let material = variant.map { primitive.effectiveMaterial(for: $0) } ?? primitive.material
        var m = try convert(material)
        m.hasTexCoord0 = uv0 != nil
        m.hasNormal = normal != nil
        // MikkTSpace above fills TANGENT when the mesh has UVs but no authored tangent.
        m.hasTangent = tangent != nil || (uv0 != nil && topology == .triangle)
        draws.append(MetalDraw(vertexBuffer:vb,indexBuffer:ib,indexCount:indices.count,primitiveType:topology,worldTransform:model,material:m,nodeIndex:asset.nodes.firstIndex(of:node) ?? -1,negativeScale:simd_determinant(model)<0,centroid:centroid,opaqueGroup:opaqueGroup))
    }

    func values(_ accessor: GLTFAccessor, components: Int) throws -> [Float] {
        let packed = GLTFPackedDataForAccessor(accessor)
        let data = accessor.componentType == .float ? packed : GLTFTransformPackedDataToFloat(packed,accessor)
        let count = accessor.count*components
        guard data.count >= count*4 else { throw MetalSceneError.invalid("Truncated accessor data") }
        return [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
            data.withUnsafeBytes { bytes in UnsafeMutableRawBufferPointer(buffer).copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[..<(count*4)])) }
            initialized = count
        }
    }
    func indexValues(_ accessor: GLTFAccessor, vertexCount: Int) throws -> [UInt32] {
        let data = GLTFPackedDataForAccessor(accessor)
        let width: Int
        switch accessor.componentType { case .unsignedByte: width=1; case .unsignedShort: width=2; case .unsignedInt: width=4; default: throw MetalSceneError.invalid("Invalid index component type") }
        let count = accessor.count
        guard data.count >= count*width else { throw MetalSceneError.invalid("Truncated index data") }
        var inRange = true
        let indices = [UInt32](unsafeUninitializedCapacity: count) { buffer, initialized in
            data.withUnsafeBytes { bytes in inRange = GLTFMetalWidenIndices(bytes.baseAddress, width, count, buffer.baseAddress, vertexCount) }
            initialized = count
        }
        guard inRange else { throw MetalSceneError.invalid("Index outside vertex buffer") }
        return indices
    }
    static func sequence(_ count: Int) -> [UInt32] {
        [UInt32](unsafeUninitializedCapacity: count) { buffer, initialized in
            GLTFMetalSequentialIndices(buffer.baseAddress, count); initialized = count
        }
    }
    /// One vertex per index (the first `count`), optionally with a face normal per triangle.
    static func deindexed(_ vertices: [MetalVertex], _ indices: [UInt32], count: Int, faceNormals: Bool) -> [MetalVertex] {
        [MetalVertex](unsafeUninitializedCapacity: count) { buffer, initialized in
            let destination = UnsafeMutableRawPointer(buffer.baseAddress)?.assumingMemoryBound(to: Float.self)
            vertices.withUnsafeBytes { source in
                let source = source.baseAddress?.assumingMemoryBound(to: Float.self)
                if faceNormals { GLTFMetalFlatNormals(destination, source, indices, count) }
                else { GLTFMetalGatherVertices(destination, source, indices, count) }
            }
            initialized = count
        }
    }
}

private extension Builder {
    func convert(_ source: GLTFMaterial?) throws -> MetalMaterial {
        guard let source else { return MetalMaterial() }
        let key = ObjectIdentifier(source)
        if let cached = materialCache[key] { return cached }
        var m = MetalMaterial()
        m.doubleSided = source.isDoubleSided; m.unlit = source.isUnlit
        m.alphaMode = Int(source.alphaMode.rawValue); m.alphaCutoff = source.alphaCutoff
        m.ior = source.indexOfRefraction?.floatValue ?? 1.5
        m.dispersion = source.dispersion?.floatValue ?? 0
        if let p = source.metallicRoughness { m.baseColor = p.baseColorFactor; m.metallic = p.metallicFactor; m.roughness = p.roughnessFactor }
        if let p = source.specularGlossiness { m.isSpecularGlossiness = true; m.baseColor = p.diffuseFactor; m.specularColor = p.specularFactor; m.glossiness = p.glossinessFactor }
        if let p = source.emissive { m.emissive = p.emissiveFactor*p.emissiveStrength }
        if let p = source.specular { m.specular = p.specularFactor; m.specularColor = p.specularColorFactor }
        if let p = source.clearcoat { m.clearcoat = p.clearcoatFactor; m.clearcoatRoughness = p.clearcoatRoughnessFactor }
        if let p = source.sheen { m.sheenColor = p.sheenColorFactor; m.sheenRoughness = p.sheenRoughnessFactor }
        if let p = source.iridescence { m.iridescence = p.iridescenceFactor; m.iridescenceIOR = p.iridescenceIndexOfRefraction; m.iridescenceThicknessMin = p.iridescenceThicknessMinimum; m.iridescenceThicknessMax = p.iridescenceThicknessMaximum }
        if let p = source.anisotropy { m.anisotropy = p.strength; m.anisotropyRotation = p.rotation }
        if let p = source.transmission { m.hasTransmission = true; m.transmission = p.transmissionFactor }
        if let p = source.volume { m.thickness = p.thicknessFactor; m.attenuationDistance = p.attenuationDistance; m.attenuationColor = p.attenuationColor }
        if let p = source.diffuseTransmission { m.diffuseTransmission = p.diffuseTransmissionFactor; m.diffuseTransmissionColor = p.diffuseTransmissionColorFactor }
        m.hasSpecular = source.specular != nil
        m.hasClearcoat = source.clearcoat != nil
        for (slot, params) in textureSlots(source) { m.textures[slot] = try binding(params, slot: slot) }
        materialCache[key] = m
        return m
    }

    /// Every texture a material binds, by slot. The specular-glossiness diffuse texture replaces
    /// the metallic-roughness base colour texture, as it did when assigned second.
    func textureSlots(_ source: GLTFMaterial) -> [(MetalTextureSlot, GLTFTextureParams)] {
        var slots: [MetalTextureSlot: GLTFTextureParams] = [:]
        func add(_ slot: MetalTextureSlot, _ params: GLTFTextureParams?) { if let params { slots[slot] = params } }
        if let p = source.metallicRoughness { add(.baseColor,p.baseColorTexture); add(.metallicRoughness,p.metallicRoughnessTexture) }
        if let p = source.specularGlossiness { add(.baseColor,p.diffuseTexture); add(.specularGlossiness,p.specularGlossinessTexture) }
        if let p = source.emissive { add(.emissive,p.emissiveTexture) }
        add(.normal,source.normalTexture); add(.occlusion,source.occlusionTexture)
        if let p = source.specular { add(.specular,p.specularTexture); add(.specularColor,p.specularColorTexture) }
        if let p = source.clearcoat { add(.clearcoat,p.clearcoatTexture); add(.clearcoatRoughness,p.clearcoatRoughnessTexture); add(.clearcoatNormal,p.clearcoatNormalTexture) }
        if let p = source.sheen { add(.sheenColor,p.sheenColorTexture); add(.sheenRoughness,p.sheenRoughnessTexture) }
        if let p = source.iridescence { add(.iridescence,p.iridescenceTexture); add(.iridescenceThickness,p.iridescenceThicknessTexture) }
        if let p = source.anisotropy { add(.anisotropy,p.anisotropyTexture) }
        if let p = source.transmission { add(.transmission,p.transmissionTexture ?? authoredTransmissionTexture(source)) }
        if let p = source.volume { add(.thickness,p.thicknessTexture) }
        if let p = source.diffuseTransmission { add(.diffuseTransmission,p.diffuseTransmissionTexture); add(.diffuseTransmissionColor,p.diffuseTransmissionColorTexture) }
        return MetalTextureSlot.allCases.compactMap { slot in slots[slot].map { (slot, $0) } }
    }

    static func image(of params: GLTFTextureParams) -> GLTFImage? {
        params.texture.basisUSource ?? params.texture.webpSource ?? params.texture.source
    }
    /// KTX2 keeps its file-declared transfer function, as the page's glUpload does.
    /// WebGL generates colour-texture mipmaps through its sRGB texture format.
    /// Sharing linear-data mips with an sRGB view averages encoded values instead.
    static func usesSRGBTexture(_ slot: MetalTextureSlot, _ image: GLTFImage) -> Bool {
        slot.isSRGB && image.inferMediaType() != GLTFMediaTypeKTX2
    }

    /// GLTFKit2 0.5.15 tests its new, empty params object instead of cgltf's texture view, so
    /// `KHR_materials_transmission.transmissionTexture` is always dropped. Read it from the JSON.
    func authoredTransmissionTexture(_ material: GLTFMaterial) -> GLTFTextureParams? {
        guard let index = asset.materials.firstIndex(of: material),
              let materials = rawJSON?["materials"] as? [[String: Any]], materials.indices.contains(index),
              let extensions = materials[index]["extensions"] as? [String: Any],
              let info = (extensions["KHR_materials_transmission"] as? [String: Any])?["transmissionTexture"] as? [String: Any],
              let textureIndex = info["index"] as? Int, asset.textures.indices.contains(textureIndex)
        else { return nil }
        let params = GLTFTextureParams()
        params.texture = asset.textures[textureIndex]
        params.texCoord = info["texCoord"] as? Int ?? 0
        params.scale = 1
        if let t = (info["extensions"] as? [String: Any])?["KHR_texture_transform"] as? [String: Any] {
            let transform = GLTFTextureTransform()
            func pair(_ key: String, _ fallback: Float) -> simd_float2 {
                let values = (t[key] as? [NSNumber])?.map(\.floatValue) ?? []
                return values.count == 2 ? simd_float2(values[0], values[1]) : simd_float2(repeating: fallback)
            }
            transform.offset = pair("offset", 0); transform.scale = pair("scale", 1)
            transform.rotation = (t["rotation"] as? NSNumber)?.floatValue ?? 0
            if let texCoord = t["texCoord"] as? Int { transform.hasTexCoord = true; transform.texCoord = Int32(texCoord) }
            params.transform = transform
        }
        return params
    }

    func binding(_ params: GLTFTextureParams, slot: MetalTextureSlot) throws -> MetalTextureBinding {
        let source = params.texture
        guard let image = Self.image(of: params) else { throw MetalSceneError.invalid("Texture has no image source") }
        let sRGB = Self.usesSRGBTexture(slot, image)
        let key = image.identifier.uuidString + (sRGB ? ":srgb" : "")
        let texture: any MTLTexture
        if let cached = textures[key] { texture = cached }
        else {
            // Only reached when `prepareTextures` did not see this binding.
            let decoded = try MetalImageLoader.decode(image: image, device: device)
            texture = try MetalImageLoader.makeTexture(decoded, device: device, sRGB: sRGB)
            if case .pixels = decoded { pendingMips.append(texture) }
            textures[key] = texture
        }
        let desc = MTLSamplerDescriptor()
        let sampler = source.sampler
        let storedMin = sampler.map { Int($0.minMipFilter.rawValue) } ?? 0
        let minFilter = storedMin == 0 ? 9987 : storedMin
        let storedMag = sampler.map { Int($0.magFilter.rawValue) } ?? 0
        let magFilter = storedMag == 0 ? 9729 : storedMag
        desc.magFilter = magFilter == 9728 ? .nearest : .linear
        desc.minFilter = [9728,9984,9986].contains(minFilter) ? .nearest : .linear
        desc.mipFilter = minFilter >= 9984 ? ([9984,9985].contains(minFilter) ? .nearest : .linear) : .notMipmapped
        if texture.mipmapLevelCount <= 1 {
            desc.mipFilter = .notMipmapped; desc.sAddressMode = .clampToEdge; desc.tAddressMode = .clampToEdge
        } else {
            func address(_ raw: Int) -> MTLSamplerAddressMode { switch raw { case 33071: .clampToEdge; case 33648: .mirrorRepeat; default: .repeat } }
            desc.sAddressMode = address(sampler.map { Int($0.wrapS.rawValue) } ?? 10497)
            desc.tAddressMode = address(sampler.map { Int($0.wrapT.rawValue) } ?? 10497)
            if [9986,9987].contains(minFilter) && magFilter != 9728 { desc.maxAnisotropy = 16 }
        }
        guard let state = device.makeSamplerState(descriptor:desc) else { throw MetalSceneError.invalid("Metal sampler allocation failed") }
        var transform = matrix_identity_float3x3
        var uv = params.texCoord
        if let t = params.transform {
            let c = cos(t.rotation), s = sin(t.rotation)
            transform = simd_float3x3(columns:(SIMD3(c*t.scale.x,-s*t.scale.x,0),SIMD3(s*t.scale.y,c*t.scale.y,0),SIMD3(t.offset.x,t.offset.y,1)))
            if t.hasTexCoord { uv = Int(t.texCoord) }
        }
        return MetalTextureBinding(texture:texture,sampler:state,texCoord:uv,transform:transform,scale:params.scale)
    }
}
