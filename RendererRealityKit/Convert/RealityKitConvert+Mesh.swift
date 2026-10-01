import GLTFCore
import RealityKit
import GLTFKit2
import simd

extension RealityKitConvert {
    // MeshResource.Contents path (skin, morph, POINTS). LowLevelMesh static meshes
    // live in RealityKitConvert+LowLevelMesh.swift.

    func convert(skin gltfSkin: GLTFSkin) -> MeshResource.Skeleton? {
        let skeletonName = gltfSkin.name ?? nextUniqueName(prefix: "Skin")
        let jointNames = gltfSkin.joints.enumerated().map { index, joint in
            JointNames.resolved(joint.name, index: index)
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
                if let packed = try convertLowLevelMesh(gltfMesh, context: context) {
                    return packed
                }
            } catch {
                AppLog.error(AppLog.load, "low-level mesh convert failed: \(error)")
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
                targetNames: targetNames,
                context: context
            )
            {
                let material = try self.convert(material: primitive.material, context: context)
                primitiveMaterialIndex += 1
                return (part, material)
            }
            context.record(
                .droppedPrimitive,
                severity: .error,
                message: "Primitive omitted (unsupported topology or convert failed)",
                materialName: primitive.material?.name
            )
            return nil
        }

        if partsAndMaterials.count == 0 {
            // If we weren't able to successfully build any parts for our primitives, don't bother generating a mesh.
            return nil
        }

        let parts = partsAndMaterials.map { $0.0 }
        let materials = partsAndMaterials.map { $0.1 }

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
        targetNames: [String] = [],
        context: RealityKitResourceContext
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

        let uvs = textureCoordinates(for: gltfPrimitive, context: context)
        if let uv0 = uvs[0] {
            part[MeshBuffers.textureCoordinates] = MeshBuffers.TextureCoordinates(uv0)
        }
        if let uv1 = uvs[1] {
            if #available(macOS 27.0, *) {
                part[MeshBuffers.textureCoordinates1] = MeshBuffers.TextureCoordinates(uv1)
            } else {
                context.record(
                    .missingTexCoord,
                    severity: .warning,
                    message: "TEXCOORD_1 on a skinned / morphed mesh needs macOS 27",
                    materialName: gltfPrimitive.material?.name
                )
            }
        }

        if let joints0Attribute = gltfPrimitive.attribute(forName: "JOINTS_0"),
           let weights0Attribute = gltfPrimitive.attribute(forName: "WEIGHTS_0"),
           let jointsArray = Packed.ushort4Array(for: joints0Attribute.accessor),
           let weightsArray = Packed.float4Array(for: weights0Attribute.accessor)
        {
            let influences = zip(jointsArray, weightsArray).flatMap { joints, weights in
                (0..<4).map { MeshJointInfluence(jointIndex: Int(joints[$0]), weight: weights[$0]) }
            }
            part.jointInfluences = MeshResource.JointInfluences(
                influences: MeshBuffers.JointInfluences(influences),
                influencesPerVertex: 4
            )
            part.skeletonID = skeletonID
        }

        let vertexCount = gltfPrimitive.attribute(forName: "POSITION")?.accessor.count ?? 0
        if let indices = triangleIndices(for: gltfPrimitive, vertexCount: vertexCount) {
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

    /// TEXCOORD_0 and TEXCOORD_1 as authored, V flipped for RealityKit. `KHR_texture_transform`
    /// and each texture's UV set are material parameters (`textureCoordinateTransform`,
    /// `Texture.uvIndex`), not baked into the vertices.
    func textureCoordinates(
        for primitive: GLTFPrimitive,
        context: RealityKitResourceContext
    ) -> [[SIMD2<Float>]?] {
        let uvs = (0..<2).map { set in
            primitive.attribute(forName: "TEXCOORD_\(set)")
                .flatMap { Packed.float2Array(for: $0.accessor, flipVertically: true) }
        }
        if let material = primitive.material {
            let needed = Set(TextureTransforms.slots(of: material).map(\.uvSet))
            if needed.contains(where: { uvs[$0] == nil }) {
                context.record(
                    .missingTexCoord,
                    severity: .error,
                    message: "Textured material has no TEXCOORD",
                    materialName: material.name
                )
            }
        }
        return uvs
    }

    func triangleIndices(for primitive: GLTFPrimitive, vertexCount: Int) -> [UInt32]? {
        if let indexAccessor = primitive.indices {
            guard let packed = Packed.uint32Array(for: indexAccessor), !packed.isEmpty else { return nil }
            return packed
        }
        return [UInt32](UInt32(0)..<UInt32(vertexCount))
    }
}
