import Foundation
import GLTFKit2

public struct AnimationClipChannel: Sendable {
    public let target: AnimationChannelTarget
    public let sampler: AnimationSampler

    public init(target: AnimationChannelTarget, sampler: AnimationSampler) {
        self.target = target
        self.sampler = sampler
    }
}

/// One glTF animation clip: channels and clip-wide `maxTime` for sampler wrapping.
public struct AnimationClip: Sendable {
    public let name: String?
    public let channels: [AnimationClipChannel]

    public init(name: String?, channels: [AnimationClipChannel]) {
        self.name = name
        self.channels = channels
    }

    /// Maximum key time across all samplers (`max` of each input accessor’s last key).
    public var maxTime: Float {
        channels.map(\.sampler.input).map { $0.last ?? 0 }.max() ?? 0
    }

    public var targetKeys: [AnimationTargetKey] {
        channels.map(\.target.key)
    }

    /// Khronos Sample Viewer default: greedily accept clips in order when targets are disjoint.
    public static func defaultSelectedClipIndices(in clips: [AnimationClip]) -> [Int] {
        var selected: [Int] = []
        var used = Set<AnimationTargetKey>()
        for (index, clip) in clips.enumerated() {
            let keys = Set(clip.targetKeys)
            if keys.isDisjoint(with: used) {
                selected.append(index)
                used.formUnion(keys)
            }
        }
        return selected
    }
}

public enum AnimationClipLoader {
    public static func loadClips(from asset: GLTFAsset) throws -> [AnimationClip] {
        try asset.animations.map { try clip(from: $0, asset: asset) }
    }

    /// Node indices whose glTF JSON includes an authored `matrix` (never TRS-animated).
    public static func matrixAuthoredNodeIndices(json: [String: Any]?) -> Set<Int> {
        guard let nodes = json?["nodes"] as? [[String: Any]] else { return [] }
        return Set(nodes.enumerated().compactMap { index, node in
            node["matrix"] != nil ? index : nil
        })
    }

    public static func matrixAuthoredNodeIndices(sourceURL: URL) -> Set<Int> {
        matrixAuthoredNodeIndices(json: rawJSONObject(at: sourceURL))
    }

    private static func clip(from animation: GLTFAnimation, asset: GLTFAsset) throws -> AnimationClip {
        let channels = try animation.channels.map { try channel(from: $0, asset: asset) }
        let maxTime = channels.map(\.sampler.input).map { $0.last ?? 0 }.max() ?? 0
        let built = channels.map { channel in
            AnimationClipChannel(
                target: channel.target,
                sampler: AnimationSampler(
                    input: channel.sampler.input,
                    output: channel.sampler.output,
                    componentCount: channel.sampler.componentCount,
                    interpolation: channel.sampler.interpolation,
                    clipMaxTime: maxTime,
                    isRotation: channel.sampler.isRotation
                )
            )
        }
        return AnimationClip(name: animation.name, channels: built)
    }

    private struct ParsedChannel {
        var target: AnimationChannelTarget
        var sampler: ParsedSampler
    }

    private struct ParsedSampler {
        var input: [Float]
        var output: [Float]
        var componentCount: Int
        var interpolation: AnimationInterpolation
        var isRotation: Bool
    }

    private static func channel(from channel: GLTFAnimationChannel, asset: GLTFAsset) throws -> ParsedChannel {
        let path = channel.target.path
        guard let node = channel.target.node, let nodeIndex = asset.nodes.firstIndex(of: node) else {
            if path.hasPrefix("/") || path.contains("/") {
                return ParsedChannel(
                    target: .pointer(path),
                    sampler: try sampler(from: channel.sampler, path: path, componentCount: 1)
                )
            }
            throw AnimationClipError.unsupportedTarget(path)
        }

        let target: AnimationChannelTarget
        switch path {
        case "translation":
            target = .translation(nodeIndex: nodeIndex)
        case "rotation":
            target = .rotation(nodeIndex: nodeIndex)
        case "scale":
            target = .scale(nodeIndex: nodeIndex)
        case "weights":
            if let nodeWeights = node.weights, !nodeWeights.isEmpty {
                target = .weightsOnNode(nodeIndex: nodeIndex)
            } else if let mesh = node.mesh, let meshIndex = asset.meshes.firstIndex(of: mesh) {
                target = .weightsOnMesh(meshIndex: meshIndex)
            } else {
                target = .weightsOnNode(nodeIndex: nodeIndex)
            }
        default:
            if path.hasPrefix("/") {
                target = .pointer(path)
            } else {
                throw AnimationClipError.unsupportedTarget(path)
            }
        }

        let componentCount: Int = switch target {
        case .translation, .scale:
            3
        case .rotation:
            4
        case .weightsOnNode:
            try weightCount(mesh: node.mesh, authored: node.weights)
        case let .weightsOnMesh(meshIndex):
            asset.meshes.indices.contains(meshIndex)
                ? try weightCount(mesh: asset.meshes[meshIndex], authored: asset.meshes[meshIndex].weights)
                : 0
        case .pointer:
            AnimationAccessorFloats.componentCount(for: channel.sampler.output)
        }

        return ParsedChannel(
            target: target,
            sampler: try sampler(from: channel.sampler, path: path, componentCount: componentCount)
        )
    }

    /// Morph weight count is the mesh's target count. Authored `weights` arrays are only a fallback
    /// for a mesh with no targets, since they are optional defaults in glTF.
    private static func weightCount(mesh: GLTFMesh?, authored: [NSNumber]?) throws -> Int {
        let targetCount = try mesh.map(morphTargetCount) ?? 0
        return targetCount > 0 ? targetCount : (authored?.count ?? 0)
    }

    /// Target count shared by every primitive of `mesh`; primitives that disagree are rejected.
    private static func morphTargetCount(of mesh: GLTFMesh) throws -> Int {
        let counts = Set(mesh.primitives.map { $0.targets.count })
        guard counts.count <= 1 else { throw AnimationClipError.mismatchedMorphTargets }
        return counts.first ?? 0
    }

    private static func sampler(
        from sampler: GLTFAnimationSampler,
        path: String,
        componentCount: Int
    ) throws -> ParsedSampler {
        let input = try AnimationAccessorFloats.values(from: sampler.input)
        let output = try AnimationAccessorFloats.values(from: sampler.output)
        let interpolation: AnimationInterpolation = switch sampler.interpolationMode {
        case .step: .step
        case .linear: .linear
        case .cubic: .cubicSpline
        @unknown default: .linear
        }
        // CUBICSPLINE stores in-tangent, value and out-tangent per key. A channel with no components
        // (no morph targets to drive) never evaluates, so only check channels that will.
        if componentCount > 0 {
            let stride = interpolation == .cubicSpline ? 3 : 1
            guard output.count == input.count * componentCount * stride else {
                throw AnimationClipError.mismatchedSampler
            }
        }
        return ParsedSampler(
            input: input,
            output: output,
            componentCount: componentCount,
            interpolation: interpolation,
            isRotation: path == "rotation"
        )
    }

    private static func rawJSONObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var json = data
        if data.count >= 20, data.prefix(4) == Data("glTF".utf8) {
            let length = data.subdata(in: 12 ..< 16).withUnsafeBytes {
                Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)))
            }
            guard data.count >= 20 + length else { return nil }
            json = data.subdata(in: 20 ..< (20 + length))
        }
        return (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
    }
}

public enum AnimationClipError: Error, Equatable {
    case unsupportedTarget(String)
    case truncatedAccessor
    case mismatchedSampler
    case mismatchedMorphTargets
}

enum AnimationAccessorFloats {
    static func values(from accessor: GLTFAccessor) throws -> [Float] {
        let packed = GLTFPackedDataForAccessor(accessor)
        let data = accessor.componentType == .float ? packed : GLTFTransformPackedDataToFloat(packed, accessor)
        let components = componentCount(for: accessor)
        let count = accessor.count * components
        guard data.count >= count * 4 else { throw AnimationClipError.truncatedAccessor }
        return [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
            data.withUnsafeBytes { bytes in
                UnsafeMutableRawBufferPointer(buffer).copyMemory(
                    from: UnsafeRawBufferPointer(rebasing: bytes[..<(count * 4)])
                )
            }
            initialized = count
        }
    }

    static func componentCount(for accessor: GLTFAccessor) -> Int {
        Int(GLTFComponentCountForDimension(accessor.dimension))
    }
}
