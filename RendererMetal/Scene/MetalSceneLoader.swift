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
    var textures: [String: any MTLTexture] = [:]
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


    func prepareTextures() async throws {
        struct ImageJob: @unchecked Sendable { let image: GLTFImage; let device: any MTLDevice }
        struct Result: @unchecked Sendable { let key: String; let texture: any MTLTexture }
        let images = asset.images.map { ImageJob(image:$0,device:device) }
        try await withThrowingTaskGroup(of:Result.self) { group in
            for job in images {
                group.addTask {
                    let texture = try MetalImageLoader.load(image:job.image,device:job.device,sRGB:false)
                    return Result(key:job.image.identifier.uuidString,texture:texture)
                }
            }
            for try await result in group { textures[result.key] = result.texture }
        }
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
        var vertices: [MetalVertex] = []
        vertices.reserveCapacity(count)
        for i in 0..<count {
            let p = SIMD4<Float>(positions[i*3], positions[i*3+1], positions[i*3+2], 1)
            let n = SIMD4<Float>(normal?[i*3] ?? 0, normal?[i*3+1] ?? 0, normal?[i*3+2] ?? 0, 0)
            let t = SIMD4<Float>(tangent?[i*4] ?? 1, tangent?[i*4+1] ?? 0, tangent?[i*4+2] ?? 0, tangent?[i*4+3] ?? 1)
            let alpha: Float = colorComponents == 4 ? (color?[i*4+3] ?? 1) : 1
            let c = SIMD4<Float>(color?[i*colorComponents] ?? 1, color?[i*colorComponents+1] ?? 1, color?[i*colorComponents+2] ?? 1, alpha)
            let u0 = SIMD2<Float>(uv0?[i*2] ?? 0, uv0?[i*2+1] ?? 0)
            let u1 = SIMD2<Float>(uv1?[i*2] ?? 0, uv1?[i*2+1] ?? 0)
            vertices.append(MetalVertex(position:p, normal:n, tangent:t, color:c, uv0:u0, uv1:u1))
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
        var indices = try primitive.indices.map { try indexValues($0) } ?? (0..<count).map(UInt32.init)
        guard indices.allSatisfy({ $0 < count }) else { throw MetalSceneError.invalid("Index outside vertex buffer") }
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
            var flat: [MetalVertex] = []; flat.reserveCapacity(indices.count)
            for i in stride(from: 0, to: indices.count - indices.count%3, by: 3) {
                var a = vertices[Int(indices[i])], b = vertices[Int(indices[i+1])], c = vertices[Int(indices[i+2])]
                let e1 = b.position-a.position, e2 = c.position-a.position
                let cross = simd_cross(SIMD3(e1.x,e1.y,e1.z),SIMD3(e2.x,e2.y,e2.z))
                let n = simd_length_squared(cross) > 0 ? simd_normalize(cross) : SIMD3<Float>(0,0,1)
                a.normal = SIMD4(n,0); b.normal = a.normal; c.normal = a.normal
                flat.append(contentsOf:[a,b,c])
            }
            vertices = flat; indices = (0..<flat.count).map(UInt32.init)
        }
        if tangent == nil && uv0 != nil && topology == .triangle {
            // A tangent discontinuity can split one indexed vertex into several corners.
            // Keep Mikk's corner results by deindexing before running its callback interface.
            var corners = indices.map { vertices[Int($0)] }
            let cornerCount = corners.count
            let generated = corners.withUnsafeMutableBytes { raw in
                GLTFMetalGenerateTangents(raw.baseAddress, cornerCount)
            }
            guard generated else { throw MetalSceneError.invalid("MikkTSpace tangent generation failed") }
            vertices = corners
            indices = (0..<corners.count).map(UInt32.init)
        }
        guard !indices.isEmpty else { return }
        for vertex in vertices {
            let p = model * vertex.position
            minimum = simd_min(minimum,SIMD3(p.x,p.y,p.z)); maximum = simd_max(maximum,SIMD3(p.x,p.y,p.z))
        }
        guard let vb = device.makeBuffer(bytes: vertices, length: vertices.count*MemoryLayout<MetalVertex>.stride, options: .storageModeShared), let ib = device.makeBuffer(bytes:indices,length:indices.count*4,options:.storageModeShared) else { throw MetalSceneError.invalid("Metal buffer allocation failed") }
        let material = variant.map { primitive.effectiveMaterial(for: $0) } ?? primitive.material
        let m = try convert(material)
        draws.append(MetalDraw(vertexBuffer:vb,indexBuffer:ib,indexCount:indices.count,primitiveType:topology,worldTransform:model,material:m,nodeIndex:asset.nodes.firstIndex(of:node) ?? -1,negativeScale:simd_determinant(model)<0))
    }

    func values(_ accessor: GLTFAccessor, components: Int) throws -> [Float] {
        let packed = GLTFPackedDataForAccessor(accessor)
        let data = accessor.componentType == .float ? packed : GLTFTransformPackedDataToFloat(packed,accessor)
        guard data.count >= accessor.count*components*4 else { throw MetalSceneError.invalid("Truncated accessor data") }
        return data.withUnsafeBytes { bytes in (0..<accessor.count*components).map { bytes.loadUnaligned(fromByteOffset:$0*4,as:Float.self) } }
    }
    func indexValues(_ accessor: GLTFAccessor) throws -> [UInt32] {
        let data = GLTFPackedDataForAccessor(accessor)
        let width: Int
        switch accessor.componentType { case .unsignedByte: width=1; case .unsignedShort: width=2; case .unsignedInt: width=4; default: throw MetalSceneError.invalid("Invalid index component type") }
        guard data.count >= accessor.count*width else { throw MetalSceneError.invalid("Truncated index data") }
        return data.withUnsafeBytes { bytes in (0..<accessor.count).map { i in switch width { case 1: UInt32(bytes.load(fromByteOffset:i,as:UInt8.self)); case 2: UInt32(bytes.loadUnaligned(fromByteOffset:i*2,as:UInt16.self)); default: bytes.loadUnaligned(fromByteOffset:i*4,as:UInt32.self) } } }
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
        func add(_ slot: MetalTextureSlot, _ params: GLTFTextureParams?) throws {
            if let params { m.textures[slot] = try binding(params, slot:slot) }
        }
        if let p = source.metallicRoughness {
            m.baseColor = p.baseColorFactor; m.metallic = p.metallicFactor; m.roughness = p.roughnessFactor
            try add(.baseColor,p.baseColorTexture); try add(.metallicRoughness,p.metallicRoughnessTexture)
        }
        if let p = source.specularGlossiness {
            m.isSpecularGlossiness = true; m.baseColor = p.diffuseFactor; m.specularColor = p.specularFactor; m.glossiness = p.glossinessFactor
            try add(.baseColor,p.diffuseTexture); try add(.specularGlossiness,p.specularGlossinessTexture)
        }
        if let p = source.emissive { m.emissive = p.emissiveFactor*p.emissiveStrength; try add(.emissive,p.emissiveTexture) }
        try add(.normal,source.normalTexture); try add(.occlusion,source.occlusionTexture)
        if let p = source.specular { m.specular = p.specularFactor; m.specularColor = p.specularColorFactor; try add(.specular,p.specularTexture); try add(.specularColor,p.specularColorTexture) }
        if let p = source.clearcoat { m.clearcoat = p.clearcoatFactor; m.clearcoatRoughness = p.clearcoatRoughnessFactor; try add(.clearcoat,p.clearcoatTexture); try add(.clearcoatRoughness,p.clearcoatRoughnessTexture); try add(.clearcoatNormal,p.clearcoatNormalTexture) }
        if let p = source.sheen { m.sheenColor = p.sheenColorFactor; m.sheenRoughness = p.sheenRoughnessFactor; try add(.sheenColor,p.sheenColorTexture); try add(.sheenRoughness,p.sheenRoughnessTexture) }
        if let p = source.iridescence { m.iridescence = p.iridescenceFactor; m.iridescenceIOR = p.iridescenceIndexOfRefraction; m.iridescenceThicknessMin = p.iridescenceThicknessMinimum; m.iridescenceThicknessMax = p.iridescenceThicknessMaximum; try add(.iridescence,p.iridescenceTexture); try add(.iridescenceThickness,p.iridescenceThicknessTexture) }
        if let p = source.anisotropy { m.anisotropy = p.strength; m.anisotropyRotation = p.rotation; try add(.anisotropy,p.anisotropyTexture) }
        if let p = source.transmission { m.transmission = p.transmissionFactor; try add(.transmission,p.transmissionTexture ?? authoredTransmissionTexture(source)) }
        if let p = source.volume { m.thickness = p.thicknessFactor; m.attenuationDistance = p.attenuationDistance; m.attenuationColor = p.attenuationColor; try add(.thickness,p.thicknessTexture) }
        if let p = source.diffuseTransmission { m.diffuseTransmission = p.diffuseTransmissionFactor; m.diffuseTransmissionColor = p.diffuseTransmissionColorFactor; try add(.diffuseTransmission,p.diffuseTransmissionTexture); try add(.diffuseTransmissionColor,p.diffuseTransmissionColorTexture) }
        materialCache[key] = m
        return m
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
        guard let image = source.basisUSource ?? source.webpSource ?? source.source else { throw MetalSceneError.invalid("Texture has no image source") }
        let key = image.identifier.uuidString
        let linearTexture: any MTLTexture
        if let cached = textures[key] { linearTexture = cached }
        else {
            linearTexture = try MetalImageLoader.load(image: image, device: device, sRGB:false)
            textures[key] = linearTexture
        }
        let texture: any MTLTexture
        if slot.isSRGB && image.inferMediaType() != GLTFMediaTypeKTX2 {
            // KTX2 keeps its file-declared transfer function, as the page's glUpload does.
            // WebGL generates colour-texture mipmaps through its sRGB texture format.
            // Sharing linear-data mips with an sRGB view averages encoded values instead.
            let colorKey = key + ":srgb"
            if let cached = textures[colorKey] { texture = cached }
            else {
                texture = try MetalImageLoader.load(image: image, device: device, sRGB: true)
                textures[colorKey] = texture
            }
        } else { texture = linearTexture }
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
