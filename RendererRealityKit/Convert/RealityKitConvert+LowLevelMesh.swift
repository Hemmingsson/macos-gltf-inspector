import GLTFCore
import RealityKit
import GLTFKit2
import Metal
import simd

extension RealityKitConvert {
    /// Build a `LowLevelMesh` with `MTLVertexFormat.float3` / `float2` layouts. Tight float
    /// bufferViews are memcpy'd (EXP-017); strided, sparse, meshopt and quantized
    /// (`KHR_mesh_quantization`, normalized ints) accessors go through one packed float copy.
    @MainActor func convertLowLevelMesh(
        _ gltfMesh: GLTFMesh,
        context: RealityKitResourceContext
    ) throws -> ModelComponent? {
        var plans: [LowLevelMeshPrimitivePlan] = []
        plans.reserveCapacity(gltfMesh.primitives.count)
        var totalVertices = 0
        var totalIndices = 0

        for primitive in gltfMesh.primitives {
            guard let plan = makeLowLevelMeshPrimitivePlan(
                primitive: primitive,
                materialIndex: plans.count,
                context: context
            ) else { return nil }

            plans.append(plan)
            totalVertices += plan.vertexCount
            totalIndices += plan.indexCount
        }

        guard !plans.isEmpty, totalVertices > 0, totalIndices > 0 else { return nil }

        let anyUVs = [0, 1].map { set in plans.contains { $0.uvs[set] != nil } }
        let meshLayout = LowLevelLayout.make(
            anyNormals: plans.contains { $0.normals != nil },
            anyTangents: plans.contains { $0.tangents != nil },
            anyUVs: anyUVs,
            anyColors: plans.contains { $0.colors != nil }
        )
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: totalVertices,
            vertexAttributes: meshLayout.attributes,
            vertexLayouts: meshLayout.layouts,
            indexCapacity: totalIndices,
            indexType: .uint32
        )
        let lowLevelMesh = try LowLevelMesh(descriptor: descriptor)

        fillLowLevelVertexBuffer(
            lowLevelMesh,
            bufferIndex: 0,
            plans: plans,
            bytesPerVertex: 12,
            write: { plan, dest in
                plan.positions.copy(elementFloats: 3, count: plan.vertexCount, to: dest)
            }
        )

        if let normalBufferIndex = meshLayout.normalBufferIndex {
            fillLowLevelVertexBuffer(
                lowLevelMesh,
                bufferIndex: normalBufferIndex,
                plans: plans,
                bytesPerVertex: 12,
                write: { plan, dest in
                    let nbytes = plan.vertexCount * 12
                    if let normals = plan.normals {
                        normals.copy(elementFloats: 3, count: plan.vertexCount, to: dest)
                    } else {
                        memset(dest, 0, nbytes)
                    }
                }
            )
        }

        if let tangentBufferIndex = meshLayout.tangentBufferIndex {
            fillLowLevelVertexBuffer(
                lowLevelMesh,
                bufferIndex: tangentBufferIndex,
                plans: plans,
                bytesPerVertex: 16,
                write: { plan, dest in
                    let nbytes = plan.vertexCount * 16
                    if let tangents = plan.tangents {
                        tangents.copy(elementFloats: 4, count: plan.vertexCount, to: dest)
                    } else {
                        memset(dest, 0, nbytes)
                    }
                }
            )
        }

        for (set, uvBufferIndex) in meshLayout.uvBufferIndices.enumerated() {
            guard let uvBufferIndex else { continue }
            fillLowLevelVertexBuffer(
                lowLevelMesh,
                bufferIndex: uvBufferIndex,
                plans: plans,
                bytesPerVertex: 8,
                write: { plan, dest in
                    let nbytes = plan.vertexCount * 8
                    if let uvs = plan.uvs[set] {
                        uvs.withUnsafeBytes { src in
                            guard let base = src.baseAddress else { return }
                            memcpy(dest, base, min(nbytes, src.count))
                        }
                    } else {
                        memset(dest, 0, nbytes)
                    }
                }
            )
        }

        if let colorBufferIndex = meshLayout.colorBufferIndex {
            fillLowLevelVertexBuffer(
                lowLevelMesh,
                bufferIndex: colorBufferIndex,
                plans: plans,
                bytesPerVertex: 16,
                write: { plan, dest in
                    let nbytes = plan.vertexCount * 16
                    if let colors = plan.colors {
                        colors.withUnsafeBytes { src in
                            guard let base = src.baseAddress else { return }
                            memcpy(dest, base, min(nbytes, src.count))
                        }
                    } else {
                        // Missing COLOR on a sibling primitive → opaque white.
                        let white = SIMD4<Float>(1, 1, 1, 1)
                        let out = dest.assumingMemoryBound(to: SIMD4<Float>.self)
                        for i in 0..<plan.vertexCount {
                            out[i] = white
                        }
                    }
                }
            )
        }

        fillLowLevelIndexBuffer(lowLevelMesh, plans: plans)

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

    /// Declared `min`/`max` for float positions; computed from the copied floats otherwise
    /// (quantized bounds are in integer units, and `min`/`max` may be missing).
    private func positionBounds(_ accessor: GLTFAccessor) -> BoundingBox? {
        if accessor.componentType == .float, let declared = boundingBox(for: accessor) {
            return declared
        }
        guard let points = Packed.float3Array(for: accessor), let first = points.first else { return nil }
        var bounds = BoundingBox(min: first, max: first)
        for point in points {
            bounds.formUnion(point)
        }
        return bounds
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

    /// One vertex attribute as float components: a tight float bufferView to memcpy, or a
    /// packed float copy (`Packed.floatData`) of anything else.
    private enum VertexFloats {
        case tight(GLTFAccessor)
        case packed(Data)

        init?(_ accessor: GLTFAccessor, dimension: GLTFValueDimension, elementFloats: Int, count: Int) {
            guard accessor.count == count, accessor.dimension == dimension else { return nil }
            if Packed.isTightFloat(accessor, dimension: dimension) {
                self = .tight(accessor)
                return
            }
            guard let data = Packed.floatData(for: accessor),
                  data.count >= count * elementFloats * MemoryLayout<Float>.size
            else { return nil }
            self = .packed(data)
        }

        func copy(elementFloats: Int, count: Int, to dest: UnsafeMutableRawPointer) {
            switch self {
            case .tight(let accessor):
                Packed.copyTight(accessor, elementFloats: elementFloats, to: dest)
            case .packed(let data):
                data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    memcpy(dest, base, count * elementFloats * MemoryLayout<Float>.size)
                }
            }
        }
    }

    private struct LowLevelMeshPrimitivePlan {
        let primitive: GLTFPrimitive
        let materialIndex: Int
        let positions: VertexFloats
        let normals: VertexFloats?
        let tangents: VertexFloats?
        let vertexCount: Int
        /// TEXCOORD_0, TEXCOORD_1 (V flipped).
        let uvs: [[SIMD2<Float>]?]
        /// Packed RGBA; RealityKit has no MeshBuffers.colors — only LowLevelMesh `.color`.
        let colors: [SIMD4<Float>]?
        let indices: [UInt32]
        let bounds: BoundingBox
        var indexCount: Int { indices.count }
    }

    private struct LowLevelLayout {
        let attributes: [LowLevelMesh.Attribute]
        let layouts: [LowLevelMesh.Layout]
        let normalBufferIndex: Int?
        let tangentBufferIndex: Int?
        let uvBufferIndices: [Int?]
        let colorBufferIndex: Int?

        static func make(
            anyNormals: Bool,
            anyTangents: Bool,
            anyUVs: [Bool],
            anyColors: Bool
        ) -> LowLevelLayout {
            var attributes: [LowLevelMesh.Attribute] = [
                .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0)
            ]
            var layouts: [LowLevelMesh.Layout] = [
                .init(bufferIndex: 0, bufferStride: 12)
            ]
            var normalBufferIndex: Int?
            var tangentBufferIndex: Int?
            var uvBufferIndices: [Int?] = [nil, nil]
            var colorBufferIndex: Int?
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
            for (set, semantic) in [LowLevelMesh.VertexSemantic.uv0, .uv1].enumerated() where anyUVs[set] {
                let idx = layouts.count
                uvBufferIndices[set] = idx
                attributes.append(.init(semantic: semantic, format: .float2, layoutIndex: idx, offset: 0))
                layouts.append(.init(bufferIndex: idx, bufferStride: 8))
            }
            if anyColors {
                let idx = layouts.count
                colorBufferIndex = idx
                attributes.append(.init(semantic: .color, format: .float4, layoutIndex: idx, offset: 0))
                layouts.append(.init(bufferIndex: idx, bufferStride: 16))
            }
            return LowLevelLayout(
                attributes: attributes,
                layouts: layouts,
                normalBufferIndex: normalBufferIndex,
                tangentBufferIndex: tangentBufferIndex,
                uvBufferIndices: uvBufferIndices,
                colorBufferIndex: colorBufferIndex
            )
        }
    }

    /// `nil` = attribute present but unusable (whole mesh falls back); `.some(nil)` = absent.
    private func optionalVertexFloats(
        _ primitive: GLTFPrimitive,
        _ name: String,
        dimension: GLTFValueDimension,
        elementFloats: Int,
        count: Int
    ) -> VertexFloats?? {
        guard let attribute = primitive.attribute(forName: name) else { return .some(nil) }
        guard let floats = VertexFloats(attribute.accessor, dimension: dimension, elementFloats: elementFloats, count: count)
        else { return nil }
        return .some(floats)
    }

    @MainActor private func makeLowLevelMeshPrimitivePlan(
        primitive: GLTFPrimitive,
        materialIndex: Int,
        context: RealityKitResourceContext
    ) -> LowLevelMeshPrimitivePlan? {
        guard primitive.primitiveType == .triangles,
              primitive.targets.isEmpty,
              primitive.attribute(forName: "JOINTS_0") == nil,
              let positionAttr = primitive.attribute(forName: "POSITION")
        else { return nil }
        let vertexCount = positionAttr.accessor.count
        guard vertexCount > 0,
              let positions = VertexFloats(positionAttr.accessor, dimension: .vector3, elementFloats: 3, count: vertexCount),
              let bounds = positionBounds(positionAttr.accessor),
              // glTF tangents are VEC4 (xyz + handedness); kept as float4.
              let normals = optionalVertexFloats(primitive, "NORMAL", dimension: .vector3, elementFloats: 3, count: vertexCount),
              let tangents = optionalVertexFloats(primitive, "TANGENT", dimension: .vector4, elementFloats: 4, count: vertexCount)
        else { return nil }

        let uvs = textureCoordinates(for: primitive, context: context)
        guard uvs.allSatisfy({ $0 == nil || $0?.count == vertexCount }) else { return nil }

        let colors: [SIMD4<Float>]?
        if let colorAttr = primitive.attribute(forName: "COLOR_0") {
            guard let packed = Packed.color4Array(for: colorAttr.accessor),
                  packed.count == vertexCount
            else { return nil }
            colors = packed
        } else {
            colors = nil
        }

        guard let indices = triangleIndices(for: primitive, vertexCount: vertexCount) else { return nil }

        return LowLevelMeshPrimitivePlan(
            primitive: primitive,
            materialIndex: materialIndex,
            positions: positions,
            normals: normals,
            tangents: tangents,
            vertexCount: vertexCount,
            uvs: uvs,
            colors: colors,
            indices: indices,
            bounds: bounds
        )
    }

    @MainActor private func fillLowLevelVertexBuffer(
        _ lowLevelMesh: LowLevelMesh,
        bufferIndex: Int,
        plans: [LowLevelMeshPrimitivePlan],
        bytesPerVertex: Int,
        write: (LowLevelMeshPrimitivePlan, UnsafeMutableRawPointer) -> Void
    ) {
        lowLevelMesh.withUnsafeMutableBytes(bufferIndex: bufferIndex) { dest in
            guard let destBase = dest.baseAddress else { return }
            var byteOffset = 0
            for plan in plans {
                write(plan, destBase + byteOffset)
                byteOffset += plan.vertexCount * bytesPerVertex
            }
        }
    }

    @MainActor private func fillLowLevelIndexBuffer(
        _ lowLevelMesh: LowLevelMesh,
        plans: [LowLevelMeshPrimitivePlan]
    ) {
        lowLevelMesh.withUnsafeMutableIndices { dest in
            guard let destBase = dest.baseAddress else { return }
            var vertexBase: UInt32 = 0
            var byteOffset = 0
            for plan in plans {
                let indexBytes = plan.indexCount * MemoryLayout<UInt32>.size
                let out = (destBase + byteOffset).assumingMemoryBound(to: UInt32.self)
                if vertexBase == 0 {
                    plan.indices.withUnsafeBufferPointer { src in
                        guard let srcBase = src.baseAddress else { return }
                        memcpy(out, srcBase, indexBytes)
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
    }
}
