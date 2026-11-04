import simd

/// Rest TRS and the load-time matrices for one glTF node. Animated components replace the rest
/// TRS; every other node keeps `localMatrix` (GLTFKit2's `node.matrix`).
struct MetalNodeRest {
    var translation: SIMD3<Float>
    var rotation: simd_quatf
    var scale: SIMD3<Float>
    var localMatrix: simd_float4x4
    var worldMatrix: simd_float4x4
    var hasMatrix: Bool
}

/// One draw's model matrix for a frame. `model` includes the node's world and its instance
/// matrix. With no TRS override these are the load-time values stored on `MetalDraw`.
struct DrawFrameTransform: Equatable, Sendable {
    var model: simd_float4x4
    var normalMatrix: simd_float4x4
    /// `det(model) < 0`. The encoder flips the front face to clockwise when this is set.
    var negativeScale: Bool
}

/// gl-matrix `fromRotationTranslationScale`: column-major Float32, T · R · S.
func gltfRotationTranslationScale(translation t: SIMD3<Float>, rotation q: simd_quatf, scale s: SIMD3<Float>) -> simd_float4x4 {
    let x = q.vector.x, y = q.vector.y, z = q.vector.z, w = q.vector.w
    let x2 = x + x, y2 = y + y, z2 = z + z
    let xx = x * x2, xy = x * y2, xz = x * z2
    let yy = y * y2, yz = y * z2, zz = z * z2
    let wx = w * x2, wy = w * y2, wz = w * z2
    return simd_float4x4(columns: (
        SIMD4((1 - (yy + zz)) * s.x, (xy + wz) * s.x, (xz - wy) * s.x, 0),
        SIMD4((xy - wz) * s.y, (1 - (xx + zz)) * s.y, (yz + wx) * s.y, 0),
        SIMD4((xz + wy) * s.z, (yz - wx) * s.z, (1 - (xx + yy)) * s.z, 0),
        SIMD4(t.x, t.y, t.z, 1)
    ))
}

extension MetalScene {
    /// Per-draw model, normal matrix and front face.
    ///
    /// No TRS override returns the cached rest worlds, the same matrices the loader baked, so a
    /// still matches the pixel references. A posed frame walks the node tree once: overridden
    /// nodes (and their descendants) recompute; everyone else keeps the cached matrix. That walk
    /// is O(nodes + draws) and is cheap next to the draw itself.
    func drawTransforms(pose: AnimationPose?) -> [DrawFrameTransform] {
        let overrides = posedOverrides(pose)
        if overrides.isEmpty { return draws.map(Self.restTransform) }

        var dirty = Array(repeating: false, count: nodeRests.count)
        func mark(_ index: Int) {
            guard nodeRests.indices.contains(index), !dirty[index] else { return }
            dirty[index] = true
            for child in nodeChildren[index] { mark(child) }
        }
        for index in overrides.keys { mark(index) }

        var worlds = nodeRests.map(\.worldMatrix)
        var resolved = Array(repeating: false, count: nodeRests.count)
        var resolving = Array(repeating: false, count: nodeRests.count)
        func resolve(_ index: Int) {
            guard nodeRests.indices.contains(index), !resolved[index], !resolving[index] else { return }
            resolving[index] = true
            let parent = nodeParents[index]
            if parent >= 0 { resolve(parent) }
            resolving[index] = false
            resolved[index] = true
            guard dirty[index] else { return }
            let rest = nodeRests[index]
            let local: simd_float4x4
            if let override = overrides[index] {
                local = gltfRotationTranslationScale(
                    translation: override.translation ?? rest.translation,
                    rotation: override.rotation ?? rest.rotation,
                    scale: override.scale ?? rest.scale
                )
            } else {
                local = rest.localMatrix
            }
            let parentWorld = parent >= 0 ? worlds[parent] : matrix_identity_float4x4
            worlds[index] = parentWorld * local
        }
        for index in nodeRests.indices where dirty[index] { resolve(index) }

        return draws.map { draw in
            let node = draw.nodeIndex
            guard nodeRests.indices.contains(node), dirty[node] else { return Self.restTransform(draw) }
            let model = worlds[node] * draw.instanceMatrix
            return DrawFrameTransform(
                model: model,
                normalMatrix: model.inverse.transpose,
                negativeScale: simd_determinant(model) < 0
            )
        }
    }

    /// TRS overrides that can move a node. Matrix-authored nodes stay on their cached local matrix.
    private func posedOverrides(_ pose: AnimationPose?) -> [Int: NodePoseOverride] {
        guard let pose else { return [:] }
        var overrides: [Int: NodePoseOverride] = [:]
        for (index, override) in pose.nodeOverrides {
            guard nodeRests.indices.contains(index), !nodeRests[index].hasMatrix else { continue }
            overrides[index] = override
        }
        return overrides
    }

    private static func restTransform(_ draw: MetalDraw) -> DrawFrameTransform {
        DrawFrameTransform(
            model: draw.worldTransform,
            normalMatrix: draw.worldTransform.inverse.transpose,
            negativeScale: draw.negativeScale
        )
    }
}
