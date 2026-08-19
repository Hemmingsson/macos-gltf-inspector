import RealityKit
import GLTFKit2
import simd

extension GLBRealityKitConvert {
    func convert(skin gltfSkin: GLTFSkin) -> MeshResource.Skeleton? {
        let skeletonName = gltfSkin.name ?? nextUniqueName(prefix: "Skin")
        let jointNames = gltfSkin.joints.enumerated().map { index, joint in
            GLBSkin.resolvedName(joint.name, index: index)
        }

        let jointParents = gltfSkin.joints.map { skeletonNode in
            if let parent = skeletonNode.parent {
                return gltfSkin.joints.firstIndex(of: parent)
            } else {
                return nil
            }
        }

        let ibmMatrices = {
            if let ibmAccessor = gltfSkin.inverseBindMatrices, let matrices = GLBPacked.float4x4(for: ibmAccessor) {
                return matrices
            } else {
                return [simd_float4x4](repeating: matrix_identity_float4x4, count: jointNames.count)
            }
        }()

        return MeshResource.Skeleton(id: skeletonName, jointNames: jointNames,
                                     inverseBindPoseMatrices: ibmMatrices, parentIndices: jointParents)
    }

    @MainActor func convert(mesh gltfMesh: GLTFMesh, skeleton: Any? /*MeshResource.Skeleton?*/ = nil,
                            context: GLBRealityKitResourceContext) throws -> RealityKit.ModelComponent?
    {
        var skeletonID: String?
        if let skeleton = skeleton as? MeshResource.Skeleton {
            skeletonID = skeleton.id
        }

        typealias PartMaterialPair = (MeshResource.Part, any RealityKit.Material)
        var primitiveMaterialIndex: Int = 0
        let partsAndMaterials = try gltfMesh.primitives.compactMap { primitive -> PartMaterialPair? in
            if let part = self.convert(primitive: primitive, materialIndex: primitiveMaterialIndex,
                                       skeletonID: skeletonID)
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
        if let skeleton = skeleton as? MeshResource.Skeleton {
            meshContents.skeletons = MeshSkeletonCollection([skeleton])
        }

        let meshResource = try MeshResource.generate(from: meshContents)
        let modelComponent = ModelComponent(mesh: meshResource, materials: materials)

        return modelComponent
    }

    func convertPoints(_ gltfPrimitive: GLTFPrimitive, materialIndex: Int) -> RealityKit.MeshResource.Part?
    {
        guard let positionAttribute = gltfPrimitive.attribute(forName: "POSITION"),
              let points = GLBPacked.float3Array(for: positionAttribute.accessor),
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

    func convert(primitive gltfPrimitive: GLTFPrimitive, materialIndex: Int = 0, skeletonID: String? = nil)
        -> RealityKit.MeshResource.Part?
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
           let positionArray = GLBPacked.float3Array(for: positionAttribute.accessor)
        {
            part[MeshBuffers.positions] = MeshBuffers.Positions(positionArray)
        }

        if let normalAttribute = gltfPrimitive.attribute(forName: "NORMAL"),
           let normalArray = GLBPacked.float3Array(for: normalAttribute.accessor)
        {
            part[MeshBuffers.normals] = MeshBuffers.Normals(normalArray)
        }

        if let tangentAttribute = gltfPrimitive.attribute(forName: "TANGENT"),
           let tangentArray = GLBPacked.float3Array(for: tangentAttribute.accessor)
        {
            part[MeshBuffers.tangents] = MeshBuffers.Tangents(tangentArray)
        }

        if let texCoordsArray = bakedTextureCoordinates(for: gltfPrimitive) {
            part[MeshBuffers.textureCoordinates] = MeshBuffers.TextureCoordinates(texCoordsArray)
        }

        if let joints0Attribute = gltfPrimitive.attribute(forName: "JOINTS_0"),
           let weights0Attribute = gltfPrimitive.attribute(forName: "WEIGHTS_0"),
           let jointsArray = GLBPacked.ushort4Array(for: joints0Attribute.accessor),
           let weightsArray = GLBPacked.float4Array(for: weights0Attribute.accessor)
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

        if let indexAccessor = gltfPrimitive.indices, let indices = GLBPacked.uint32Array(for: indexAccessor) {
            part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        } else {
            let vertexCount = gltfPrimitive.attribute(forName: "POSITION")?.accessor.count ?? 0
            let indices = [UInt32](UInt32(0)..<UInt32(vertexCount))
            part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        }

        return part
    }
    /// Bake `KHR_texture_transform` in glTF space (`T * R * S`), then flip V for RealityKit.
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
              var uvs = GLBPacked.float2Array(for: attribute.accessor, flipVertically: false)
        else { return nil }
        if let transform = params?.transform {
            let matrix = transform.matrix
            uvs = uvs.map { uv in
                let p = matrix * SIMD4(uv.x, uv.y, 0, 1)
                return SIMD2(p.x, p.y)
            }
        }
        return uvs.map { SIMD2($0.x, 1 - $0.y) }
    }
}
