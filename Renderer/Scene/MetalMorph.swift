import Metal
import simd

/// Morph attributes Khronos sums in the vertex shader, in slot order. Bit `1 << slot` is the mask.
enum MorphSlot {
    static let position = 0
    static let normal = 1
    static let tangent = 2
    static let texCoord0 = 3
    static let texCoord1 = 4
    static let color0 = 5
    static let count = 6

    static func index(for name: String) -> Int? {
        switch name {
        case "POSITION": position
        case "NORMAL": normal
        case "TANGENT": tangent
        case "TEXCOORD_0": texCoord0
        case "TEXCOORD_1": texCoord1
        case "COLOR_0": color0
        default: nil
        }
    }

    /// Packed-slot ordinal of `slot` given which bits of `mask` are stored.
    static func ordinal(mask: UInt32, slot: Int) -> Int {
        let below = mask & UInt32(truncatingIfNeeded: (1 << slot) - 1)
        return below.nonzeroBitCount
    }
}

extension MetalDraw {
    /// One gathered delta. `slot` is a `MorphSlot` index, not a packed ordinal.
    func morphDelta(slot: Int, target: Int, vertex emitted: Int) -> SIMD4<Float>? {
        guard let morphBuffer, let morphSourceOfBuffer, (0..<MorphSlot.count).contains(slot),
              morphMask & (1 << UInt32(slot)) != 0,
              (0..<morphTargetCount).contains(target),
              (0..<morphVertexCount).contains(emitted),
              morphSourceVertexCount > 0 else { return nil }
        let map = morphSourceOfBuffer.contents().bindMemory(to: UInt32.self, capacity: morphVertexCount)
        let source = Int(map[emitted])
        guard source >= 0, source < morphSourceVertexCount else { return nil }
        let ordinal = MorphSlot.ordinal(mask: morphMask, slot: slot)
        let index = (ordinal * morphTargetCount + target) * morphSourceVertexCount + source
        let count = morphBuffer.length / MemoryLayout<SIMD4<Float>>.stride
        guard index < count else { return nil }
        return morphBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)[index]
    }
}

extension MetalScene {
    /// Node pose weights win over mesh pose weights. No pose entry keeps the authored rest weights.
    func morphWeights(for draw: MetalDraw, pose: AnimationPose?) -> [Float] {
        let count = draw.morphTargetCount
        guard count > 0 else { return [] }
        let source: [Float]
        if let pose, let node = pose.nodeWeights[draw.nodeIndex] {
            source = node
        } else if let pose, let mesh = pose.meshWeights[draw.meshIndex] {
            source = mesh
        } else {
            source = draw.restWeights
        }
        if source.count == count { return source }
        var weights = [Float](repeating: 0, count: count)
        for index in 0..<min(count, source.count) { weights[index] = source[index] }
        return weights
    }
}
