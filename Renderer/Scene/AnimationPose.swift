import Foundation
import simd

/// Per-node TRS overrides sampled from active clips (omit components that were not animated).
public struct NodePoseOverride: Sendable, Equatable {
    public var translation: SIMD3<Float>?
    public var rotation: simd_quatf?
    public var scale: SIMD3<Float>?

    public init(
        translation: SIMD3<Float>? = nil,
        rotation: simd_quatf? = nil,
        scale: SIMD3<Float>? = nil
    ) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }
}

/// Pose at time *t* from one or more clips: TRS overrides and morph weights only for animated targets.
public struct AnimationPose: Sendable, Equatable {
    public var nodeOverrides: [Int: NodePoseOverride]
    public var nodeWeights: [Int: [Float]]
    public var meshWeights: [Int: [Float]]

    public init(
        nodeOverrides: [Int: NodePoseOverride] = [:],
        nodeWeights: [Int: [Float]] = [:],
        meshWeights: [Int: [Float]] = [:]
    ) {
        self.nodeOverrides = nodeOverrides
        self.nodeWeights = nodeWeights
        self.meshWeights = meshWeights
    }

    /// Evaluates `clips` at `time`, skipping TRS on `matrixAuthoredNodes` and ignoring pointer targets.
    public init(clips: [AnimationClip], at time: Float, matrixAuthoredNodes: Set<Int> = [], wraps: Bool = true) {
        var nodeOverrides: [Int: NodePoseOverride] = [:]
        var nodeWeights: [Int: [Float]] = [:]
        var meshWeights: [Int: [Float]] = [:]

        for clip in clips {
            let sampleTime = wraps ? time : min(time, clip.maxTime)
            for channel in clip.channels {
                let values = channel.sampler.evaluate(at: sampleTime, wraps: wraps)
                guard !values.isEmpty else { continue }

                switch channel.target {
                case let .translation(nodeIndex):
                    guard !matrixAuthoredNodes.contains(nodeIndex) else { continue }
                    var entry = nodeOverrides[nodeIndex] ?? NodePoseOverride()
                    entry.translation = SIMD3(values[0], values[1], values[2])
                    nodeOverrides[nodeIndex] = entry
                case let .rotation(nodeIndex):
                    guard !matrixAuthoredNodes.contains(nodeIndex) else { continue }
                    var entry = nodeOverrides[nodeIndex] ?? NodePoseOverride()
                    entry.rotation = simd_quatf(
                        vector: SIMD4(values[0], values[1], values[2], values[3])
                    )
                    nodeOverrides[nodeIndex] = entry
                case let .scale(nodeIndex):
                    guard !matrixAuthoredNodes.contains(nodeIndex) else { continue }
                    var entry = nodeOverrides[nodeIndex] ?? NodePoseOverride()
                    entry.scale = SIMD3(values[0], values[1], values[2])
                    nodeOverrides[nodeIndex] = entry
                case let .weightsOnNode(nodeIndex):
                    nodeWeights[nodeIndex] = values
                case let .weightsOnMesh(meshIndex):
                    meshWeights[meshIndex] = values
                case .pointer:
                    continue
                }
            }
        }

        self.nodeOverrides = nodeOverrides
        self.nodeWeights = nodeWeights
        self.meshWeights = meshWeights
    }
}
