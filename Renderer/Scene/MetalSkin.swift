import simd

/// One glTF skin: joint node indices into `asset.nodes` and the inverse bind matrices.
/// Joint matrices for a frame are `world[joint] * inverseBind`, built from the same node walk
/// as `framePose` (including joints that sit outside the scene).
struct MetalSkin {
    var jointNodeIndices: [Int]
    var inverseBindMatrices: [simd_float4x4]
}

/// Per emitted vertex. 48 bytes, matching `SkinVertex` in `pbr.metal` (two ushort4, two float4).
struct MetalSkinVertex {
    var joints0: SIMD4<UInt16>
    var joints1: SIMD4<UInt16>
    var weights0: SIMD4<Float>
    var weights1: SIMD4<Float>
}

/// One joint's matrix and its normal matrix (`transpose(inverse(joint))`), not the inverse of a blend.
struct GPUJointPair {
    var joint: simd_float4x4
    var normal: simd_float4x4
}

enum MetalSkinning {
    /// `setVertexBytes` accepts at most 4 KB. A pair is 128 bytes, so 32 joints is the largest
    /// palette that fits; more than that uses a real buffer.
    static let vertexBytesLimit = 4096

    static func palette(skin: MetalSkin, worlds: [simd_float4x4]) -> [GPUJointPair] {
        skin.jointNodeIndices.enumerated().map { index, node in
            let world = worlds.indices.contains(node) ? worlds[node] : matrix_identity_float4x4
            let ibm = inverseBindMatrices(skin, index: index)
            let joint = world * ibm
            return GPUJointPair(joint: joint, normal: normalMatrix(joint))
        }
    }

    static func normalMatrix(_ joint: simd_float4x4) -> simd_float4x4 {
        guard abs(simd_determinant(joint)) > 1e-12 else { return matrix_identity_float4x4 }
        return simd_transpose(simd_inverse(joint))
    }

    /// Column-major glTF matrix `index` from a packed float accessor, or identity when absent.
    static func gltfMatrix(_ values: [Float]?, index: Int) -> simd_float4x4 {
        guard let values else { return matrix_identity_float4x4 }
        let base = index * 16
        guard values.count >= base + 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(columns: (
            SIMD4(values[base], values[base + 1], values[base + 2], values[base + 3]),
            SIMD4(values[base + 4], values[base + 5], values[base + 6], values[base + 7]),
            SIMD4(values[base + 8], values[base + 9], values[base + 10], values[base + 11]),
            SIMD4(values[base + 12], values[base + 13], values[base + 14], values[base + 15])
        ))
    }

    private static func inverseBindMatrices(_ skin: MetalSkin, index: Int) -> simd_float4x4 {
        skin.inverseBindMatrices.indices.contains(index) ? skin.inverseBindMatrices[index] : matrix_identity_float4x4
    }
}
