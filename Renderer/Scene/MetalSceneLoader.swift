import Foundation
import GLTFCore
import GLTFKit2
import Metal
import simd

public enum MetalSceneLoader {
    private static let dracoConfiguration: Void = {
        GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"
    }()

    public static func load(url: URL, device: any MTLDevice, sceneIndex: Int? = nil, materialVariantIndex: Int? = nil) async throws -> MetalScene {
        try MetalMeshoptPreprocessor.preflight(url: url)
        _ = dracoConfiguration
        return try await Task.detached(priority: .userInitiated) {
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
    var skins: [MetalSkin] = []
    var morphBufferCache: [ObjectIdentifier: any MTLBuffer] = [:]
    var morphSourceOfCache: [ObjectIdentifier: any MTLBuffer] = [:]
    var nodeIndexByIdentity: [ObjectIdentifier: Int] = [:]
    var meshIndexByIdentity: [ObjectIdentifier: Int] = [:]
    var skinIndexByIdentity: [ObjectIdentifier: Int] = [:]
    var materialIndexByIdentity: [ObjectIdentifier: Int] = [:]
    var primitiveIndexByIdentity: [ObjectIdentifier: Int] = [:]
    let sourceURL: URL
    init(asset: GLTFAsset, device: any MTLDevice, sourceURL: URL) { self.asset = asset; self.device = device; self.sourceURL = sourceURL }

    func buildIdentityIndexMaps() {
        nodeIndexByIdentity = Dictionary(asset.nodes.enumerated().map { (ObjectIdentifier($1), $0) }, uniquingKeysWith: { first, _ in first })
        meshIndexByIdentity = Dictionary(asset.meshes.enumerated().map { (ObjectIdentifier($1), $0) }, uniquingKeysWith: { first, _ in first })
        skinIndexByIdentity = Dictionary(asset.skins.enumerated().map { (ObjectIdentifier($1), $0) }, uniquingKeysWith: { first, _ in first })
        materialIndexByIdentity = Dictionary(asset.materials.enumerated().map { (ObjectIdentifier($1), $0) }, uniquingKeysWith: { first, _ in first })
        primitiveIndexByIdentity = [:]
        for mesh in asset.meshes {
            for (index, primitive) in mesh.primitives.enumerated() {
                primitiveIndexByIdentity[ObjectIdentifier(primitive)] = index
            }
        }
    }

    func nodeIndex(_ node: GLTFNode) -> Int { nodeIndexByIdentity[ObjectIdentifier(node)] ?? -1 }
    /// The source file's JSON (GLB chunk or .gltf), for extension fields GLTFKit2 parses incorrectly.
    lazy var rawJSON: [String: Any]? = AnimationClipLoader.rawJSONObject(at: sourceURL)


    /// Decodes every image a material binds once, then makes the linear and/or sRGB textures its
    /// slots need and generates all their mips in one command buffer.
    func prepareTextures() async throws {
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
        var mipmapped: [any MTLTexture] = []
        for entry in usage.values {
            let decoded = try MetalImageLoader.decode(image: entry.image, device: device)
            let key = entry.image.identifier.uuidString
            if case let .texture(texture) = decoded {
                textures[key] = texture
                continue
            }
            let linear = entry.linear ? try MetalImageLoader.makeTexture(decoded, device: device, sRGB: false) : nil
            let sRGB = entry.sRGB ? try MetalImageLoader.makeTexture(decoded, device: device, sRGB: true) : nil
            if let linear { textures[key] = linear; mipmapped.append(linear) }
            if let sRGB { textures[key + ":srgb"] = sRGB; mipmapped.append(sRGB) }
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
        buildIdentityIndexMaps()
        try rejectParentCycles()
        let variant: GLTFMaterialVariant?
        if let materialVariantIndex, let variants = asset.materialVariants {
            guard variants.indices.contains(materialVariantIndex) else { throw MetalSceneError.invalid("Material variant index is out of range") }
            variant = variants[materialVariantIndex]
        } else { variant = nil }
        var inSceneNodes = Set<Int>()
        var visibleNodes = Set<Int>()
        func collect(_ node: GLTFNode, _ parent: simd_float4x4) {
            let index = nodeIndex(node)
            if index >= 0 { inSceneNodes.insert(index) }
            let transform = parent * node.matrix
            world[ObjectIdentifier(node)] = transform
            for child in node.childNodes { collect(child, transform) }
        }
        for node in scene.nodes { collect(node, matrix_identity_float4x4) }
        // Joints may be outside the selected scene tree.
        for skin in asset.skins { for joint in skin.joints { _ = cachedWorld(joint) } }
        skins = try makeSkins()
        func visit(_ node: GLTFNode, visible: Bool) throws {
            let authoredVisibility = (node.extensions["KHR_node_visibility"] as? [String: Any])?["visible"] as? Bool ?? true
            guard visible && authoredVisibility else { return }
            let index = nodeIndex(node)
            if index >= 0 { visibleNodes.insert(index) }
            let transform = world[ObjectIdentifier(node)] ?? matrix_identity_float4x4
            if let light = node.light {
                let p = transform * SIMD4<Float>(0, 0, 0, 1)
                let d = transform * SIMD4<Float>(0, 0, -1, 0)
                // Map GLTFKit2 light types (1...3) to the shader types (0...2).
                lights.append(MetalPunctualLight(type: Int(light.type.rawValue) - 1, position: SIMD3(p.x,p.y,p.z), direction: simd_normalize(SIMD3(d.x,d.y,d.z)), color: light.color, intensity: light.intensity, range: light.range, innerConeCos: cos(light.innerConeAngle), outerConeCos: cos(light.outerConeAngle), nodeIndex: nodeIndex(node)))
            }
            if let mesh = node.mesh {
                let instances = node.meshInstances
                for i in 0..<(instances?.instanceCount ?? 1) {
                    let instance = instances?.transform(at: i) ?? matrix_identity_float4x4
                    let model = transform * instance
                    for primitive in mesh.primitives { try append(primitive, node: node, model: model, instance: instance, variant: variant) }
                }
            }
            for child in node.childNodes { try visit(child, visible: true) }
        }
        for node in scene.nodes { try visit(node, visible: true) }
        if draws.isEmpty {
            minimum = .zero
            maximum = .zero
        }
        try MetalImageLoader.generateMipmaps(pendingMips, device: device)
        pendingMips.removeAll()
        let skinJointNodeIndices = skins.map(\.jointNodeIndices)
        let jointNodeSet = Set(skinJointNodeIndices.flatMap { $0 })
        let matrixAuthoredNodes = AnimationClipLoader.matrixAuthoredNodeIndices(json: rawJSON)
        let clips: [AnimationClip]
        do {
            clips = try AnimationClipLoader.loadClips(from: asset)
        } catch {
            AppLog.error(AppLog.renderer, "animation clips failed during load: \(error)")
            clips = []
        }
        return MetalScene(draws: draws, boundsMin: minimum, boundsMax: maximum, lights: lights, asset: asset,
                          nodeRests: nodeRests(matrixAuthoredNodes: matrixAuthoredNodes), skins: skins,
                          inSceneNodes: inSceneNodes, visibleNodes: visibleNodes,
                          skinJointNodeIndices: skinJointNodeIndices, jointNodeSet: jointNodeSet,
                          clips: clips, matrixAuthoredNodes: matrixAuthoredNodes)
    }

    func rejectParentCycles() throws {
        let indices = nodeIndexByIdentity
        var parents = [Int](repeating: -1, count: asset.nodes.count)
        for (index, node) in asset.nodes.enumerated() {
            if let parent = node.parent, let parentIndex = indices[ObjectIdentifier(parent)] {
                parents[index] = parentIndex
            }
        }
        for start in asset.nodes.indices {
            var seen = Set<Int>()
            var current = start
            while parents.indices.contains(current), current >= 0 {
                guard seen.insert(current).inserted else {
                    throw MetalSceneError.invalid("The glTF scene graph contains a cycle")
                }
                current = parents[current]
            }
        }
        var children = Array(repeating: [Int](), count: asset.nodes.count)
        for (index, node) in asset.nodes.enumerated() {
            children[index] = node.childNodes.compactMap { indices[ObjectIdentifier($0)] }
        }
        var visiting = Set<Int>()
        var visited = Set<Int>()
        func visit(_ index: Int) throws {
            if visiting.contains(index) {
                throw MetalSceneError.invalid("The glTF scene graph contains a cycle")
            }
            if visited.contains(index) { return }
            visiting.insert(index)
            for child in children[index] { try visit(child) }
            visiting.remove(index)
            visited.insert(index)
        }
        for index in asset.nodes.indices where !visited.contains(index) {
            try visit(index)
        }
    }

    /// Cached `parent * matrix` world, filling joints (and other nodes) outside the scene walk.
    func cachedWorld(_ node: GLTFNode) -> simd_float4x4 {
        if let value = world[ObjectIdentifier(node)] { return value }
        let value = (node.parent.map { cachedWorld($0) } ?? matrix_identity_float4x4) * node.matrix
        world[ObjectIdentifier(node)] = value
        return value
    }

    /// Cached rest worlds. Nodes the scene walk did not reach (a joint outside the scene) get the
    /// same `parent * matrix` the loader uses for them.
    func nodeRests(matrixAuthoredNodes matrixNodes: Set<Int>) -> [MetalNodeRest] {
        asset.nodes.enumerated().map { index, node in
            MetalNodeRest(
                translation: node.translation,
                rotation: node.rotation,
                scale: node.scale,
                localMatrix: node.matrix,
                worldMatrix: cachedWorld(node),
                hasMatrix: matrixNodes.contains(index)
            )
        }
    }

    func append(_ primitive: GLTFPrimitive, node: GLTFNode, model: simd_float4x4, instance: simd_float4x4, variant: GLTFMaterialVariant?) throws {
        guard let accessor = primitive.attribute(forName: "POSITION")?.accessor else { throw MetalSceneError.invalid("Primitive has no POSITION accessor") }
        let count = accessor.count
        guard count > 0 else { return }
        try validate(accessor, components: 3, name: "POSITION")
        try Self.validateVertexCount(count)
        let positions = try values(accessor, components: 3)
        func attribute(_ name: String, _ n: Int) throws -> [Float]? {
            guard let a = primitive.attribute(forName: name)?.accessor else { return nil }
            guard a.count == count else { throw MetalSceneError.invalid("Mismatched \(name) accessor count") }
            try validate(a, components: n, name: name)
            return try values(a, components: n)
        }
        let normal = try attribute("NORMAL", 3)
        let tangent = try attribute("TANGENT", 4)
        let uv0 = try attribute("TEXCOORD_0", 2)
        let uv1 = try attribute("TEXCOORD_1", 2)
        let colorAccessor = primitive.attribute(forName: "COLOR_0")?.accessor
        let colorComponents = colorAccessor?.dimension == .vector3 ? 3 : 4
        let color = try attribute("COLOR_0", colorComponents)
        var vertices = [MetalVertex](repeating: MetalVertex(position: .zero, normal: .zero, tangent: .zero,
                                                            color: .zero, uv0: .zero, uv1: .zero), count: count)
        let packed = vertices.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            GLTFMetalPackVertices(base.assumingMemoryBound(to: Float.self), count,
                                  positions, normal, tangent, color, colorComponents, uv0, uv1)
            return true
        }
        guard packed else { throw MetalSceneError.invalid("Vertex buffer is empty") }
        guard count <= Int(UInt32.max) else { throw MetalSceneError.invalid("Vertex count is too large") }
        var sourceOf = (0..<count).map { UInt32($0) }
        // Bind-pose attributes. Skinning happens in the shader; these feeds are gathered after deindex.
        let joints0 = try attribute("JOINTS_0", 4)
        let weights0 = try attribute("WEIGHTS_0", 4)
        let joints1 = try attribute("JOINTS_1", 4)
        let weights1 = try attribute("WEIGHTS_1", 4)
        var indices = try primitive.indices.map { try indexValues($0, vertexCount: count) } ?? Self.sequence(count)
        // Khronos Primitive.computeCentroid: Float32 accumulation over the authored indices and POSITIONs.
        var sum = SIMD3<Float>(repeating: 0)
        for index in indices { let i = Int(index) * 3; sum += SIMD3(positions[i], positions[i+1], positions[i+2]) }
        let centroid = SIMD3<Float>(sum.indices.map { Float(Double(sum[$0]) / Double(indices.count)) })
        // Khronos opaque instancing groups: skins, morph targets, GPU instancing and the
        // attribute limit (glAttributes + 4 > 16 on Apple WebGL2) each get their own group.
        let meshIndex = node.mesh.flatMap { meshIndexByIdentity[ObjectIdentifier($0)] } ?? -1
        let primitiveIndex = primitiveIndexByIdentity[ObjectIdentifier(primitive)] ?? -1
        let winding = simd_determinant(model) > 0 ? 1 : (simd_determinant(model) < 0 ? -1 : 0)
        var opaqueGroup = "\(meshIndex)_\(winding)_\(primitiveIndex)"
        if node.skin != nil || !primitive.targets.isEmpty || node.meshInstances != nil || primitive.attributes.count + 4 > 16 {
            opaqueGroup += "_node\(nodeIndex(node))"
        }
        let topology: MTLPrimitiveType
        switch primitive.primitiveType.rawValue - 1 {
        case 0: topology = .point
        case 1: topology = .line
        case 2:
            _ = try MetalResourceLimits.product(indices.count, 2 * MemoryLayout<UInt32>.stride,
                                                label: "Line loop indices", limit: MetalResourceLimits.maxSingleAllocationBytes)
            indices = indices.indices.flatMap { i in [indices[i], indices[(i+1)%indices.count]] }; topology = .line
        case 3: topology = .lineStrip
        case 4: topology = .triangle
        case 5:
            _ = try MetalResourceLimits.product(max(0, indices.count - 2), 3 * MemoryLayout<UInt32>.stride,
                                                label: "Triangle strip indices", limit: MetalResourceLimits.maxSingleAllocationBytes)
            let source = indices
            indices = source.count < 3 ? [] : (2..<source.count).flatMap { i in i%2 == 0 ? [source[i-2],source[i-1],source[i]] : [source[i-1],source[i-2],source[i]] }; topology = .triangle
        case 6:
            _ = try MetalResourceLimits.product(max(0, indices.count - 2), 3 * MemoryLayout<UInt32>.stride,
                                                label: "Triangle fan indices", limit: MetalResourceLimits.maxSingleAllocationBytes)
            let source = indices
            indices = source.count < 3 ? [] : (2..<source.count).flatMap { [source[0],source[$0-1],source[$0]] }; topology = .triangle
        default: throw MetalSceneError.invalid("Unsupported primitive topology")
        }
        let morphPositionTargets = Self.hasPositionMorphTargets(primitive)
        if normal == nil && topology == .triangle {
            // Khronos generates a face normal when absent: split shared vertices to preserve hard edges.
            // With POSITION morph targets and no NORMAL, leave zeros so the shader derives from morphed position.
            let flatCount = indices.count - indices.count%3
            try Self.validateVertexCount(flatCount)
            let sources = Array(indices.prefix(flatCount))
            vertices = Self.deindexed(vertices, indices, count: flatCount, faceNormals: !morphPositionTargets)
            if morphPositionTargets {
                for index in vertices.indices { vertices[index].normal = .zero }
            }
            sourceOf = sources.map { sourceOf[Int($0)] }
            indices = Self.sequence(flatCount)
        }
        if tangent == nil && uv0 != nil && topology == .triangle && !morphPositionTargets {
            // A tangent discontinuity can split one indexed vertex into several corners.
            // Keep Mikk's corner results by deindexing before running its callback interface.
            try Self.validateVertexCount(indices.count)
            let sources = indices
            var corners = Self.deindexed(vertices, indices, count: indices.count, faceNormals: false)
            let cornerCount = corners.count
            let generated = corners.withUnsafeMutableBytes { raw in
                GLTFMetalGenerateTangents(raw.baseAddress, cornerCount)
            }
            guard generated else { throw MetalSceneError.invalid("MikkTSpace tangent generation failed") }
            vertices = corners
            sourceOf = sources.map { sourceOf[Int($0)] }
            indices = Self.sequence(corners.count)
        }
        if morphPositionTargets && tangent == nil {
            for index in vertices.indices {
                vertices[index].tangent = .zero
            }
        }
        guard !indices.isEmpty else { return }
        let morph = try gatherMorph(primitive, sourceCount: count, sourceOf: sourceOf)
        let targetCount = primitive.targets.count
        var restWeights = [Float](repeating: 0, count: targetCount)
        let authored = (node.weights ?? node.mesh?.weights ?? []).map(\.floatValue)
        for index in 0..<min(targetCount, authored.count) { restWeights[index] = authored[index] }
        let skinIndex = node.skin.flatMap { skinIndexByIdentity[ObjectIdentifier($0)] }
        let hasJoints1 = joints1 != nil && weights1 != nil
        let skinVerts: [MetalSkinVertex]
        if let skinIndex, let joints0, let weights0 {
            guard skins.indices.contains(skinIndex) else { throw MetalSceneError.invalid("Skin index is out of range") }
            skinVerts = try gatheredSkin(joints0: joints0, weights0: weights0, joints1: hasJoints1 ? joints1 : nil,
                                         weights1: hasJoints1 ? weights1 : nil, sourceOf: sourceOf,
                                         jointCount: skins[skinIndex].jointNodeIndices.count)
        } else if node.skin != nil {
            throw MetalSceneError.invalid("Skinned primitive is missing JOINTS_0 or WEIGHTS_0")
        } else {
            skinVerts = []
        }
        var boundsVertices = vertices
        if let morph, morph.mask & (1 << MorphSlot.position) != 0, restWeights.contains(where: { $0 != 0 }) {
            let ordinal = MorphSlot.ordinal(mask: morph.mask, slot: MorphSlot.position)
            for vertex in boundsVertices.indices {
                let source = Int(sourceOf[vertex])
                var position = boundsVertices[vertex].position
                for target in 0..<morph.targetCount where target < restWeights.count && restWeights[target] != 0 {
                    let delta = morph.deltas[(ordinal * morph.targetCount + target) * morph.sourceCount + source]
                    position += SIMD4(delta.x, delta.y, delta.z, 0) * restWeights[target]
                }
                boundsVertices[vertex].position = position
            }
        }
        // Morph first, then the same object-space blend the CPU bake used, so camera fit stays.
        // Weights are renormalized here only: the GPU path does not, matching Khronos.
        if let skinIndex, !skinVerts.isEmpty {
            let matrices = objectSpaceJoints(skinIndex: skinIndex, model: model)
            for vertex in boundsVertices.indices {
                var blended = simd_float4x4(0)
                var total: Float = 0
                func accumulate(_ joints: SIMD4<UInt16>, _ weights: SIMD4<Float>) {
                    for component in 0..<4 {
                        let weight = weights[component]
                        let joint = Int(joints[component])
                        guard weight != 0, matrices.indices.contains(joint) else { continue }
                        blended += matrices[joint] * weight
                        total += weight
                    }
                }
                accumulate(skinVerts[vertex].joints0, skinVerts[vertex].weights0)
                if hasJoints1 { accumulate(skinVerts[vertex].joints1, skinVerts[vertex].weights1) }
                if total > 0 {
                    blended *= 1 / total
                    var position = boundsVertices[vertex].position
                    position.w = 1
                    boundsVertices[vertex].position = blended * position
                }
            }
        }
        withUnsafeBytes(of: model) { matrix in
            withUnsafeMutableBytes(of: &minimum) { lo in
                withUnsafeMutableBytes(of: &maximum) { hi in
                    boundsVertices.withUnsafeBytes { raw in
                        guard let vertices = raw.baseAddress?.assumingMemoryBound(to: Float.self),
                              let matrix = matrix.baseAddress?.assumingMemoryBound(to: Float.self),
                              let lo = lo.baseAddress?.assumingMemoryBound(to: Float.self),
                              let hi = hi.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
                        GLTFMetalBounds(vertices, boundsVertices.count, matrix, lo, hi)
                    }
                }
            }
        }
        let vertexBytes = try MetalResourceLimits.product(vertices.count, MemoryLayout<MetalVertex>.stride,
                                                           label: "Vertex buffer", limit: MetalResourceLimits.maxSingleAllocationBytes)
        let indexBytes = try MetalResourceLimits.product(indices.count, MemoryLayout<UInt32>.stride,
                                                          label: "Index buffer", limit: MetalResourceLimits.maxSingleAllocationBytes)
        guard let vb = device.makeBuffer(bytes: vertices, length: vertexBytes, options: .storageModeShared),
              let ib = device.makeBuffer(bytes: indices, length: indexBytes, options: .storageModeShared)
        else { throw MetalSceneError.invalid("Metal buffer allocation failed") }
        let primitiveKey = ObjectIdentifier(primitive)
        let morphBuffer: (any MTLBuffer)?
        if let morph, !morph.deltas.isEmpty {
            if let cached = morphBufferCache[primitiveKey] {
                morphBuffer = cached
            } else {
                let byteCount = try MetalResourceLimits.product(morph.deltas.count, MemoryLayout<SIMD4<Float>>.stride,
                                                                 label: "Morph buffer", limit: MetalResourceLimits.maxSingleAllocationBytes)
                guard let buffer = device.makeBuffer(bytes: morph.deltas, length: byteCount, options: .storageModeShared) else {
                    throw MetalSceneError.invalid("Metal buffer allocation failed")
                }
                morphBufferCache[primitiveKey] = buffer
                morphBuffer = buffer
            }
        } else { morphBuffer = nil }
        let morphSourceOfBuffer: (any MTLBuffer)?
        if morphBuffer != nil {
            if let cached = morphSourceOfCache[primitiveKey] {
                morphSourceOfBuffer = cached
            } else {
                let byteCount = try MetalResourceLimits.product(sourceOf.count, MemoryLayout<UInt32>.stride,
                                                                 label: "Morph source buffer", limit: MetalResourceLimits.maxSingleAllocationBytes)
                guard let buffer = device.makeBuffer(bytes: sourceOf, length: byteCount, options: .storageModeShared) else {
                    throw MetalSceneError.invalid("Metal buffer allocation failed")
                }
                morphSourceOfCache[primitiveKey] = buffer
                morphSourceOfBuffer = buffer
            }
        } else { morphSourceOfBuffer = nil }
        let skinBuffer: (any MTLBuffer)?
        if !skinVerts.isEmpty {
            let byteCount = try MetalResourceLimits.product(skinVerts.count, MemoryLayout<MetalSkinVertex>.stride,
                                                             label: "Skin buffer", limit: MetalResourceLimits.maxSingleAllocationBytes)
            guard let buffer = device.makeBuffer(bytes: skinVerts, length: byteCount, options: .storageModeShared) else {
                throw MetalSceneError.invalid("Metal buffer allocation failed")
            }
            skinBuffer = buffer
        } else { skinBuffer = nil }
        let material = variant.map { primitive.effectiveMaterial(for: $0) } ?? primitive.material
        let gltfMaterialIndex = material.flatMap { materialIndexByIdentity[ObjectIdentifier($0)] }
        var m = try convert(material)
        m.hasTexCoord0 = uv0 != nil
        m.hasNormal = normal != nil
        // MikkTSpace above fills TANGENT when the mesh has UVs but no authored tangent.
        m.hasTangent = tangent != nil || (uv0 != nil && topology == .triangle && !morphPositionTargets)
        draws.append(MetalDraw(vertexBuffer:vb,indexBuffer:ib,indexCount:indices.count,primitiveType:topology,worldTransform:model,instanceMatrix:instance,material:m,gltfMaterialIndex:gltfMaterialIndex,nodeIndex:nodeIndex(node),negativeScale:simd_determinant(model)<0,centroid:centroid,opaqueGroup:opaqueGroup,meshIndex:meshIndex,restWeights:restWeights,morphBuffer:morphBuffer,morphTargetCount:targetCount,morphSourceVertexCount:morph?.sourceCount ?? 0,morphSourceOfBuffer:morphSourceOfBuffer,morphVertexCount:vertices.count,morphMask:morph?.mask ?? 0,skinBuffer:skinBuffer,skinIndex:skinVerts.isEmpty ? nil : skinIndex,hasJoints1:hasJoints1 && !skinVerts.isEmpty))
    }

    func makeSkins() throws -> [MetalSkin] {
        let indexOf = Dictionary(asset.nodes.enumerated().map { (ObjectIdentifier($1), $0) }, uniquingKeysWith: { first, _ in first })
        return try asset.skins.map { skin in
            let matrices: [simd_float4x4]
            if let accessor = skin.inverseBindMatrices {
                guard accessor.count == skin.joints.count else {
                    throw MetalSceneError.invalid("Skin inverse bind matrices do not match its joints")
                }
                try validate(accessor, components: 16, name: "inverse bind matrix")
                guard accessor.componentType == .float else {
                    throw MetalSceneError.invalid("Inverse bind matrices must use FLOAT")
                }
                let raw = try values(accessor, components: 16)
                matrices = skin.joints.indices.map { MetalSkinning.gltfMatrix(raw, index: $0) }
            } else {
                matrices = Array(repeating: matrix_identity_float4x4, count: skin.joints.count)
            }
            return MetalSkin(
                jointNodeIndices: skin.joints.map { indexOf[ObjectIdentifier($0)] ?? -1 },
                inverseBindMatrices: matrices
            )
        }
    }

    /// Object-space joint matrices for rest bounds: `inverse(model) * world * IBM`. Multiplying
    /// back by `model` in `GLTFMetalBounds` recovers `world * IBM` when the weights sum to 1,
    /// and still applies `model` to a vertex whose weights sum to 0.
    func objectSpaceJoints(skinIndex: Int, model: simd_float4x4) -> [simd_float4x4] {
        let skin = skins[skinIndex]
        let inverseModel = simd_inverse(model)
        return skin.jointNodeIndices.enumerated().map { index, node in
            let jointWorld: simd_float4x4
            if asset.nodes.indices.contains(node) {
                jointWorld = world[ObjectIdentifier(asset.nodes[node])] ?? matrix_identity_float4x4
            } else {
                jointWorld = matrix_identity_float4x4
            }
            let ibm = skin.inverseBindMatrices.indices.contains(index) ? skin.inverseBindMatrices[index] : matrix_identity_float4x4
            return inverseModel * jointWorld * ibm
        }
    }

    func gatheredSkin(joints0: [Float], weights0: [Float], joints1: [Float]?, weights1: [Float]?, sourceOf: [UInt32],
                      jointCount: Int) throws -> [MetalSkinVertex] {
        func joint(_ values: [Float], source: Int, component: Int) throws -> UInt16 {
            let raw = values[source * 4 + component]
            guard raw.isFinite, raw >= 0, raw.rounded() == raw, raw < Float(jointCount) else {
                throw MetalSceneError.invalid("Skin joint index is out of range")
            }
            return UInt16(raw)
        }
        func weights(_ values: [Float], source: Int) throws -> SIMD4<Float> {
            let base = source * 4
            let result = SIMD4(values[base], values[base + 1], values[base + 2], values[base + 3])
            guard result.x.isFinite && result.y.isFinite && result.z.isFinite && result.w.isFinite,
                  result.x >= 0 && result.y >= 0 && result.z >= 0 && result.w >= 0 else {
                throw MetalSceneError.invalid("Skin weights are invalid")
            }
            return result
        }
        return try sourceOf.map { source in
            let index = Int(source)
            var vertex = MetalSkinVertex(joints0: .zero, joints1: .zero, weights0: try weights(weights0, source: index), weights1: .zero)
            vertex.joints0 = SIMD4(
                try joint(joints0, source: index, component: 0), try joint(joints0, source: index, component: 1),
                try joint(joints0, source: index, component: 2), try joint(joints0, source: index, component: 3)
            )
            if let joints1, let weights1 {
                vertex.joints1 = SIMD4(
                    try joint(joints1, source: index, component: 0), try joint(joints1, source: index, component: 1),
                    try joint(joints1, source: index, component: 2), try joint(joints1, source: index, component: 3)
                )
                vertex.weights1 = try weights(weights1, source: index)
            }
            return vertex
        }
    }

    /// Deltas for the emitted vertices. Layout is `[present slot][target][vertex]`, slot order
    /// matching `MorphSlot` (only attributes some target actually carries).
    func gatherMorph(_ primitive: GLTFPrimitive, sourceCount: Int, sourceOf: [UInt32]) throws -> (deltas: [SIMD4<Float>], mask: UInt32, targetCount: Int, sourceCount: Int)? {
        let targets = primitive.targets
        guard !targets.isEmpty else { return nil }
        var mask: UInt32 = 0
        for target in targets {
            for attribute in target {
                if let slot = MorphSlot.index(for: attribute.name ?? "") { mask |= 1 << UInt32(slot) }
            }
        }
        let targetCount = targets.count
        guard mask != 0 else { return (deltas: [], mask: 0, targetCount: targetCount, sourceCount: sourceCount) }
        var present: [Int] = []
        for slot in 0..<MorphSlot.count where mask & (1 << UInt32(slot)) != 0 { present.append(slot) }
        let deltaCount = try MetalResourceLimits.product(present.count, targetCount, label: "Morph target count")
        let totalDeltaCount = try MetalResourceLimits.product(deltaCount, sourceCount, label: "Morph data",
                                                               limit: MetalResourceLimits.maxSingleAllocationBytes / MemoryLayout<SIMD4<Float>>.stride)
        var deltas = [SIMD4<Float>](repeating: .zero, count: totalDeltaCount)
        for (targetIndex, target) in targets.enumerated() {
            for attribute in target {
                guard let slot = MorphSlot.index(for: attribute.name ?? ""), let ordinal = present.firstIndex(of: slot) else { continue }
                let components = Int(GLTFComponentCountForDimension(attribute.accessor.dimension))
                guard attribute.accessor.count == sourceCount else { throw MetalSceneError.invalid("Mismatched morph accessor count") }
                try validate(attribute.accessor, components: components, name: attribute.name ?? "morph target")
                let data = try values(attribute.accessor, components: components)
                for source in 0..<sourceCount {
                    var value = SIMD4<Float>(repeating: 0)
                    let base = source * components
                    for component in 0..<min(components, 4) { value[component] = data[base + component] }
                    deltas[(ordinal * targetCount + targetIndex) * sourceCount + source] = value
                }
            }
        }
        return (deltas, mask, targetCount, sourceCount)
    }

    func validate(_ accessor: GLTFAccessor, components: Int, name: String) throws {
        guard accessor.count >= 0,
              Int(GLTFComponentCountForDimension(accessor.dimension)) == components else {
            throw MetalSceneError.invalid("\(name) accessor has the wrong dimension")
        }
        switch name {
        case "POSITION", "inverse bind matrix":
            guard accessor.componentType == .float else {
                throw MetalSceneError.invalid("\(name) accessor must use FLOAT")
            }
        case "NORMAL", "TANGENT":
            switch accessor.componentType {
            case .float, .byte, .unsignedByte, .short, .unsignedShort:
                break
            default:
                throw MetalSceneError.invalid("\(name) accessor has an unsupported component type")
            }
        case "JOINTS_0", "JOINTS_1":
            guard accessor.componentType == .unsignedByte || accessor.componentType == .unsignedShort else {
                throw MetalSceneError.invalid("\(name) accessor must use UNSIGNED_BYTE or UNSIGNED_SHORT")
            }
        case "TEXCOORD_0", "TEXCOORD_1", "COLOR_0", "WEIGHTS_0", "WEIGHTS_1":
            switch accessor.componentType {
            case .float, .byte, .unsignedByte, .short, .unsignedShort:
                break
            default:
                throw MetalSceneError.invalid("\(name) accessor has an unsupported component type")
            }
        default:
            break
        }
    }

    func values(_ accessor: GLTFAccessor, components: Int) throws -> [Float] {
        guard accessor.count >= 0, components > 0,
              Int(GLTFComponentCountForDimension(accessor.dimension)) == components else {
            throw MetalSceneError.invalid("Accessor dimension does not match the requested attributes")
        }
        let count = try MetalResourceLimits.product(accessor.count, components, label: "Accessor element count",
                                                     limit: MetalResourceLimits.maxSingleAllocationBytes / MemoryLayout<Float>.stride)
        let byteCount = try MetalResourceLimits.product(count, MemoryLayout<Float>.stride, label: "Accessor data",
                                                         limit: MetalResourceLimits.maxSingleAllocationBytes)
        let packed: Data
        do {
            packed = try GLTFAccessorData.packed(accessor)
        } catch GLTFAccessorDataError.invalidRange {
            throw MetalSceneError.invalid("Accessor data is out of bounds")
        }
        let data = accessor.componentType == .float ? packed : GLTFTransformPackedDataToFloat(packed,accessor)
        guard data.count >= byteCount else { throw MetalSceneError.invalid("Truncated accessor data") }
        return data.withUnsafeBytes { bytes in
            Array(UnsafeRawBufferPointer(rebasing: bytes[..<byteCount]).bindMemory(to: Float.self))
        }
    }
    func indexValues(_ accessor: GLTFAccessor, vertexCount: Int) throws -> [UInt32] {
        let width: Int
        switch accessor.componentType { case .unsignedByte: width=1; case .unsignedShort: width=2; case .unsignedInt: width=4; default: throw MetalSceneError.invalid("Invalid index component type") }
        let count = accessor.count
        let byteCount = try MetalResourceLimits.product(count, width, label: "Index data",
                                                         limit: MetalResourceLimits.maxSingleAllocationBytes)
        _ = try MetalResourceLimits.product(count, MemoryLayout<UInt32>.stride, label: "Expanded index data",
                                             limit: MetalResourceLimits.maxSingleAllocationBytes)
        let data: Data
        do {
            data = try GLTFAccessorData.packed(accessor)
        } catch GLTFAccessorDataError.invalidRange {
            throw MetalSceneError.invalid("Accessor data is out of bounds")
        }
        guard data.count >= byteCount else { throw MetalSceneError.invalid("Truncated index data") }
        var inRange = true
        let indices = try data.withUnsafeBytes { bytes -> [UInt32] in
            guard let base = bytes.baseAddress else { throw MetalSceneError.invalid("Index data is empty") }
            var values = [UInt32](repeating: 0, count: count)
            values.withUnsafeMutableBufferPointer { output in
                inRange = GLTFMetalWidenIndices(base, width, count, output.baseAddress, vertexCount)
            }
            return values
        }
        guard inRange else { throw MetalSceneError.invalid("Index outside vertex buffer") }
        return indices
    }
    static func hasPositionMorphTargets(_ primitive: GLTFPrimitive) -> Bool {
        primitive.targets.contains { target in
            target.contains { MorphSlot.index(for: $0.name ?? "") == MorphSlot.position }
        }
    }

    static func validateVertexCount(_ count: Int) throws {
        _ = try MetalResourceLimits.product(count, MemoryLayout<MetalVertex>.stride,
                                            label: "Expanded vertices", limit: MetalResourceLimits.maxSingleAllocationBytes)
    }

    static func sequence(_ count: Int) -> [UInt32] {
        var result = [UInt32](repeating: 0, count: count)
        result.withUnsafeMutableBufferPointer { output in
            GLTFMetalSequentialIndices(output.baseAddress, count)
        }
        return result
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
    /// KTX2 keeps its file-declared transfer function, as the viewer's glUpload does.
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
        // Material samplers are encoded into the fragment argument buffer.
        desc.supportArgumentBuffers = true
        let sampler = source.sampler
        let storedMin = sampler.map { Int($0.minMipFilter.rawValue) } ?? 0
        let minFilter = storedMin == 0 ? 9987 : storedMin
        let storedMag = sampler.map { Int($0.magFilter.rawValue) } ?? 0
        let magFilter = storedMag == 0 ? 9729 : storedMag
        desc.magFilter = magFilter == 9728 ? .nearest : .linear
        desc.minFilter = [9728,9984,9986].contains(minFilter) ? .nearest : .linear
        desc.mipFilter = minFilter >= 9984 ? ([9984,9985].contains(minFilter) ? .nearest : .linear) : .notMipmapped
        if texture.mipmapLevelCount <= 1 {
            desc.mipFilter = .notMipmapped
        } else if [9986,9987].contains(minFilter) && magFilter != 9728 {
            desc.maxAnisotropy = 16
        }
        func address(_ raw: Int) -> MTLSamplerAddressMode { switch raw { case 33071: .clampToEdge; case 33648: .mirrorRepeat; default: .repeat } }
        desc.sAddressMode = address(sampler.map { Int($0.wrapS.rawValue) } ?? 10497)
        desc.tAddressMode = address(sampler.map { Int($0.wrapT.rawValue) } ?? 10497)
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
