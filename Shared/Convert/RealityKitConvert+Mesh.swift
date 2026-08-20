import RealityKit
import GLTFKit2
import Metal
import simd

extension RealityKitConvert {
    func convert(skin gltfSkin: GLTFSkin) -> MeshResource.Skeleton? {
        let skeletonName = gltfSkin.name ?? nextUniqueName(prefix: "Skin")
        let jointNames = gltfSkin.joints.enumerated().map { index, joint in
            Skin.resolvedName(joint.name, index: index)
        }

        let jointParents = gltfSkin.joints.map { skeletonNode in
            if let parent = skeletonNode.parent {
                return gltfSkin.joints.firstIndex(of: parent)
            } else {
                return nil
            }
        }

        let ibmMatrices: [simd_float4x4] = {
            let identity = [simd_float4x4](repeating: matrix_identity_float4x4, count: jointNames.count)
            guard let ibmAccessor = gltfSkin.inverseBindMatrices, let matrices = Packed.float4x4(for: ibmAccessor) else {
                return identity
            }
            if matrices.count == jointNames.count { return matrices }
            if matrices.count > jointNames.count { return Array(matrices.prefix(jointNames.count)) }
            return matrices + identity.dropFirst(matrices.count)
        }()

        return MeshResource.Skeleton(id: skeletonName, jointNames: jointNames,
                                     inverseBindPoseMatrices: ibmMatrices, parentIndices: jointParents)
    }

    @MainActor func convert(
        mesh gltfMesh: GLTFMesh,
        skeleton: MeshResource.Skeleton? = nil,
        context: RealityKitResourceContext
    ) throws -> RealityKit.ModelComponent?
    {
        if skeleton == nil {
            do {
                if let packed = try convertTightFloatMesh(gltfMesh, context: context) {
                    return packed
                }
            } catch {
                AppLog.error(AppLog.load, "tight float mesh convert failed: \(error)")
            }
        }

        let skeletonID = skeleton?.id

        typealias PartMaterialPair = (MeshResource.Part, any RealityKit.Material)
        var primitiveMaterialIndex: Int = 0
        let targetNames = morphTargetNames(for: gltfMesh)
        let partsAndMaterials = try gltfMesh.primitives.compactMap { primitive -> PartMaterialPair? in
            if let part = self.convert(
                primitive: primitive,
                materialIndex: primitiveMaterialIndex,
                skeletonID: skeletonID,
                targetNames: targetNames
            )
            {
                let material = try self.convert(material: primitive.material, context: context)
                primitiveMaterialIndex += 1
                return (part, material)
            }
            // If we fail to create a part from a primitive, omit it from the list.
            return nil
        }

        if partsAndMaterials.count == 0 {
            // If we weren't able to successfully build any parts for our primitives, don't bother generating a mesh.
            return nil
        }

        let parts = partsAndMaterials.map { $0.0 }
        let materials = partsAndMaterials.map { $0.1 }
        
        // TODO: This only ensures uniqueness for unnamed meshes; the asset could still contain duplicate names.
        let modelName = gltfMesh.name ?? nextUniqueName(prefix: "Mesh")
        let model = MeshResource.Model(id: modelName, parts: parts)

        var meshContents = MeshResource.Contents()
        meshContents.models = MeshModelCollection([model])
        if let skeleton {
            meshContents.skeletons = MeshSkeletonCollection([skeleton])
        }

        let meshResource = try MeshResource.generate(from: meshContents)
        let modelComponent = ModelComponent(mesh: meshResource, materials: materials)

        return modelComponent
    }

    /// Build a `LowLevelMesh` with `MTLVertexFormat.float3` / `float2` layouts and
    /// memcpy tight glTF bufferViews (no `[SIMD3<Float>]` expansion).
    @MainActor private func convertTightFloatMesh(
        _ gltfMesh: GLTFMesh,
        context: RealityKitResourceContext
    ) throws -> ModelComponent? {
        struct Plan {
            let primitive: GLTFPrimitive
            let materialIndex: Int
            let positions: GLTFAccessor
            let normals: GLTFAccessor?
            let tangents: GLTFAccessor?
            let bakedUVs: [SIMD2<Float>]?
            let indices: [UInt32]
            let bounds: BoundingBox
            var vertexCount: Int { positions.count }
            var indexCount: Int { indices.count }
        }

        var plans: [Plan] = []
        plans.reserveCapacity(gltfMesh.primitives.count)
        var totalVertices = 0
        var totalIndices = 0
        var anyNormals = false
        var anyTangents = false
        var anyUVs = false

        for primitive in gltfMesh.primitives {
            guard primitive.primitiveType == .triangles,
                  primitive.targets.isEmpty,
                  primitive.attribute(forName: "JOINTS_0") == nil,
                  let positionAttr = primitive.attribute(forName: "POSITION"),
                  Packed.isTightFloat(positionAttr.accessor, dimension: .vector3),
                  let bounds = boundingBox(for: positionAttr.accessor)
            else { return nil }

            let normalsAccessor: GLTFAccessor?
            if let normalAttr = primitive.attribute(forName: "NORMAL") {
                guard Packed.isTightFloat(normalAttr.accessor, dimension: .vector3),
                      normalAttr.accessor.count == positionAttr.accessor.count
                else { return nil }
                normalsAccessor = normalAttr.accessor
                anyNormals = true
            } else {
                normalsAccessor = nil
            }

            let tangentsAccessor: GLTFAccessor?
            if let tangentAttr = primitive.attribute(forName: "TANGENT") {
                // glTF tangents are VEC4 (xyz + handedness); keep packed float4 as-is.
                guard Packed.isTightFloat(tangentAttr.accessor, dimension: .vector4),
                      tangentAttr.accessor.count == positionAttr.accessor.count
                else { return nil }
                tangentsAccessor = tangentAttr.accessor
                anyTangents = true
            } else {
                tangentsAccessor = nil
            }

            let bakedUVs = bakedTextureCoordinates(for: primitive)
            if let bakedUVs {
                guard bakedUVs.count == positionAttr.accessor.count else { return nil }
                anyUVs = true
            }

            let indices: [UInt32]
            if let indexAccessor = primitive.indices {
                guard let packed = Packed.uint32Array(for: indexAccessor), !packed.isEmpty else { return nil }
                indices = packed
            } else {
                let count = positionAttr.accessor.count
                indices = [UInt32](UInt32(0)..<UInt32(count))
            }

            plans.append(
                Plan(
                    primitive: primitive,
                    materialIndex: plans.count,
                    positions: positionAttr.accessor,
                    normals: normalsAccessor,
                    tangents: tangentsAccessor,
                    bakedUVs: bakedUVs,
                    indices: indices,
                    bounds: bounds
                )
            )
            totalVertices += positionAttr.accessor.count
            totalIndices += indices.count
        }

        guard !plans.isEmpty, totalVertices > 0, totalIndices > 0 else { return nil }

        var attributes: [LowLevelMesh.Attribute] = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0)
        ]
        var layouts: [LowLevelMesh.Layout] = [
            .init(bufferIndex: 0, bufferStride: 12)
        ]
        var normalBufferIndex: Int?
        var tangentBufferIndex: Int?
        var uvBufferIndex: Int?
        if anyNormals {
            let idx = layouts.count
            normalBufferIndex = idx
            attributes.append(.init(semantic: .normal, format: .float3, layoutIndex: idx, offset: 0))
            layouts.append(.init(bufferIndex: idx, bufferStride: 12))
        }
        if anyTangents {
            let idx = layouts.count
            tangentBufferIndex = idx
            attributes.append(.init(semantic: .tangent, format: .float4, layoutIndex: idx, offset: 0))
            layouts.append(.init(bufferIndex: idx, bufferStride: 16))
        }
        if anyUVs {
            let idx = layouts.count
            uvBufferIndex = idx
            attributes.append(.init(semantic: .uv0, format: .float2, layoutIndex: idx, offset: 0))
            layouts.append(.init(bufferIndex: idx, bufferStride: 8))
        }

        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: totalVertices,
            vertexAttributes: attributes,
            vertexLayouts: layouts,
            indexCapacity: totalIndices,
            indexType: .uint32
        )
        let lowLevelMesh = try LowLevelMesh(descriptor: descriptor)

        lowLevelMesh.withUnsafeMutableBytes(bufferIndex: 0) { dest in
            var byteOffset = 0
            for plan in plans {
                let nbytes = plan.vertexCount * 12
                Packed.copyTight(plan.positions, elementFloats: 3, to: dest.baseAddress! + byteOffset)
                byteOffset += nbytes
            }
        }

        if let normalBufferIndex {
            lowLevelMesh.withUnsafeMutableBytes(bufferIndex: normalBufferIndex) { dest in
                var byteOffset = 0
                for plan in plans {
                    let nbytes = plan.vertexCount * 12
                    if let normals = plan.normals {
                        Packed.copyTight(normals, elementFloats: 3, to: dest.baseAddress! + byteOffset)
                    } else {
                        memset(dest.baseAddress! + byteOffset, 0, nbytes)
                    }
                    byteOffset += nbytes
                }
            }
        }

        if let tangentBufferIndex {
            lowLevelMesh.withUnsafeMutableBytes(bufferIndex: tangentBufferIndex) { dest in
                var byteOffset = 0
                for plan in plans {
                    let nbytes = plan.vertexCount * 16
                    if let tangents = plan.tangents {
                        Packed.copyTight(tangents, elementFloats: 4, to: dest.baseAddress! + byteOffset)
                    } else {
                        memset(dest.baseAddress! + byteOffset, 0, nbytes)
                    }
                    byteOffset += nbytes
                }
            }
        }

        if let uvBufferIndex {
            lowLevelMesh.withUnsafeMutableBytes(bufferIndex: uvBufferIndex) { dest in
                var byteOffset = 0
                for plan in plans {
                    let nbytes = plan.vertexCount * 8
                    if let uvs = plan.bakedUVs {
                        uvs.withUnsafeBytes { src in
                            guard let base = src.baseAddress else { return }
                            memcpy(dest.baseAddress! + byteOffset, base, min(nbytes, src.count))
                        }
                    } else {
                        memset(dest.baseAddress! + byteOffset, 0, nbytes)
                    }
                    byteOffset += nbytes
                }
            }
        }

        lowLevelMesh.withUnsafeMutableIndices { dest in
            var vertexBase: UInt32 = 0
            var byteOffset = 0
            for plan in plans {
                let indexBytes = plan.indexCount * MemoryLayout<UInt32>.size
                let out = (dest.baseAddress! + byteOffset).assumingMemoryBound(to: UInt32.self)
                if vertexBase == 0 {
                    plan.indices.withUnsafeBufferPointer { src in
                        _ = memcpy(out, src.baseAddress!, indexBytes)
                    }
                } else {
                    for i in 0..<plan.indexCount {
                        out[i] = plan.indices[i] &+ vertexBase
                    }
                }
                byteOffset += indexBytes
                vertexBase &+= UInt32(plan.vertexCount)
            }
        }

        var parts: [LowLevelMesh.Part] = []
        parts.reserveCapacity(plans.count)
        var indexByteOffset = 0
        for plan in plans {
            parts.append(
                LowLevelMesh.Part(
                    indexOffset: indexByteOffset,
                    indexCount: plan.indexCount,
                    topology: .triangle,
                    materialIndex: plan.materialIndex,
                    bounds: plan.bounds
                )
            )
            indexByteOffset += plan.indexCount * MemoryLayout<UInt32>.size
        }
        lowLevelMesh.parts.replaceAll(parts)

        let meshResource = try MeshResource(from: lowLevelMesh)
        let materials: [any RealityKit.Material] = try plans.map { plan in
            try convert(material: plan.primitive.material, context: context)
        }
        return ModelComponent(mesh: meshResource, materials: materials)
    }

    private func boundingBox(for positionAccessor: GLTFAccessor) -> BoundingBox? {
        let mins = positionAccessor.minValues
        let maxs = positionAccessor.maxValues
        guard mins.count >= 3, maxs.count >= 3 else { return nil }
        let minP = SIMD3<Float>(mins[0].floatValue, mins[1].floatValue, mins[2].floatValue)
        let maxP = SIMD3<Float>(maxs[0].floatValue, maxs[1].floatValue, maxs[2].floatValue)
        guard minP.x.isFinite, minP.y.isFinite, minP.z.isFinite,
              maxP.x.isFinite, maxP.y.isFinite, maxP.z.isFinite
        else { return nil }
        return BoundingBox(min: minP, max: maxP)
    }

    func convertPoints(_ gltfPrimitive: GLTFPrimitive, materialIndex: Int) -> RealityKit.MeshResource.Part?
    {
        guard let positionAttribute = gltfPrimitive.attribute(forName: "POSITION"),
              let points = Packed.float3Array(for: positionAttribute.accessor),
              !points.isEmpty
        else { return nil }
        var minBound = points[0]
        var maxBound = points[0]
        for point in points {
            minBound = simd_min(minBound, point)
            maxBound = simd_max(maxBound, point)
        }
        let size = max(0.0005, simd_length(maxBound - minBound) * 0.004)
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(points.count * 3)
        indices.reserveCapacity(points.count * 3)
        for point in points {
            let base = UInt32(positions.count)
            positions.append(point + SIMD3(size, 0, 0))
            positions.append(point + SIMD3(0, size, 0))
            positions.append(point + SIMD3(0, 0, size))
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
        let partName = nextUniqueName(prefix: "Points")
        var part = MeshResource.Part(id: partName, materialIndex: materialIndex)
        part[MeshBuffers.positions] = MeshBuffers.Positions(positions)
        part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        return part
    }

    func convert(
        primitive gltfPrimitive: GLTFPrimitive,
        materialIndex: Int = 0,
        skeletonID: String? = nil,
        targetNames: [String] = []
    ) -> RealityKit.MeshResource.Part?
    {
        switch gltfPrimitive.primitiveType {
        case .points:
            return convertPoints(gltfPrimitive, materialIndex: materialIndex)
        case .triangles:
            break
        default:
            return nil
        }

        let partName = nextUniqueName(prefix: "Primitive")
        var part = MeshResource.Part(id: partName, materialIndex: materialIndex)

        if let positionAttribute = gltfPrimitive.attribute(forName: "POSITION"),
           let positionArray = Packed.float3Array(for: positionAttribute.accessor)
        {
            part[MeshBuffers.positions] = MeshBuffers.Positions(positionArray)
        }

        if let normalAttribute = gltfPrimitive.attribute(forName: "NORMAL"),
           let normalArray = Packed.float3Array(for: normalAttribute.accessor)
        {
            part[MeshBuffers.normals] = MeshBuffers.Normals(normalArray)
        }

        if let tangentAttribute = gltfPrimitive.attribute(forName: "TANGENT"),
           let tangentArray = Packed.float3Array(for: tangentAttribute.accessor)
        {
            part[MeshBuffers.tangents] = MeshBuffers.Tangents(tangentArray)
        }

        if let texCoordsArray = bakedTextureCoordinates(for: gltfPrimitive) {
            part[MeshBuffers.textureCoordinates] = MeshBuffers.TextureCoordinates(texCoordsArray)
        }

        if let joints0Attribute = gltfPrimitive.attribute(forName: "JOINTS_0"),
           let weights0Attribute = gltfPrimitive.attribute(forName: "WEIGHTS_0"),
           let jointsArray = Packed.ushort4Array(for: joints0Attribute.accessor),
           let weightsArray = Packed.float4Array(for: weights0Attribute.accessor)
        {
            let weightsPerVertex = 4
            func jointInfluences(forJoints joints: [SIMD4<UInt16>], weights: [SIMD4<Float>]) -> [MeshJointInfluence] {
                return zip(joints, weights).reduce(into: [MeshJointInfluence]()) { partialResult, jointsAndWeights in
                    let joints = jointsAndWeights.0; let weights = jointsAndWeights.1
                    partialResult.append(MeshJointInfluence(jointIndex: Int(joints[0]), weight: weights[0]))
                    partialResult.append(MeshJointInfluence(jointIndex: Int(joints[1]), weight: weights[1]))
                    partialResult.append(MeshJointInfluence(jointIndex: Int(joints[2]), weight: weights[2]))
                    partialResult.append(MeshJointInfluence(jointIndex: Int(joints[3]), weight: weights[3]))
                }
            }

            let influences = jointInfluences(forJoints: jointsArray, weights: weightsArray)
            part.jointInfluences = MeshResource.JointInfluences(influences: MeshBuffers.JointInfluences(influences),
                                                                influencesPerVertex: weightsPerVertex)
            part.skeletonID = skeletonID
        }

        // TODO: Support explicit bitangents and other user attributes?

        if let indexAccessor = gltfPrimitive.indices, let indices = Packed.uint32Array(for: indexAccessor) {
            part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        } else {
            let vertexCount = gltfPrimitive.attribute(forName: "POSITION")?.accessor.count ?? 0
            let indices = [UInt32](UInt32(0)..<UInt32(vertexCount))
            part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        }

        applyMorphTargets(to: &part, primitive: gltfPrimitive, targetNames: targetNames)
        return part
    }

    func morphTargetNames(for mesh: GLTFMesh) -> [String] {
        let named = mesh.targetNames ?? []
        let count = mesh.primitives.map(\.targets.count).max() ?? 0
        return (0..<count).map { index in
            if index < named.count, !named[index].isEmpty {
                return named[index]
            }
            return "Morph\(index)"
        }
    }

    /// glTF morph targets are per-vertex position deltas (optional NORMAL/TANGENT ignored).
    private func applyMorphTargets(
        to part: inout MeshResource.Part,
        primitive: GLTFPrimitive,
        targetNames: [String]
    ) {
        for (index, target) in primitive.targets.enumerated() {
            let position = target.first { $0.name == "POSITION" }
            guard let accessor = position?.accessor,
                  let offsets = Packed.float3Array(for: accessor),
                  !offsets.isEmpty
            else { continue }
            let name = index < targetNames.count ? targetNames[index] : "Morph\(index)"
            part.setBlendShapeOffsets(named: name, buffer: MeshBuffers.BlendShapeOffsets(offsets))
        }
    }
    /// Bake `KHR_texture_transform` in glTF space (`T * R * S`), wrap a single
    /// UDIM tile into 0–1, then flip V for RealityKit.
    private func bakedTextureCoordinates(for primitive: GLTFPrimitive) -> [SIMD2<Float>]? {
        let params = primitive.material?.metallicRoughness?.baseColorTexture
            ?? primitive.material?.normalTexture
        let texCoord: Int
        if let transform = params?.transform, transform.hasTexCoord {
            texCoord = Int(transform.texCoord)
        } else {
            texCoord = params?.texCoord ?? 0
        }
        let attribute = primitive.attribute(forName: "TEXCOORD_\(texCoord)")
            ?? primitive.attribute(forName: "TEXCOORD_0")
        guard let attribute,
              var uvs = Packed.float2Array(for: attribute.accessor, flipVertically: false)
        else { return nil }
        if let transform = params?.transform {
            let matrix = transform.matrix
            uvs = uvs.map { uv in
                let p = matrix * SIMD4(uv.x, uv.y, 0, 1)
                return SIMD2(p.x, p.y)
            }
        }
        uvs = TextureUV.wrapSingleTile(uvs)
        return uvs.map { SIMD2($0.x, 1 - $0.y) }
    }
}
