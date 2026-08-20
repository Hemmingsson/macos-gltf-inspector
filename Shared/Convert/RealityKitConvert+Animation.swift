import RealityKit
import GLTFKit2

extension RealityKitConvert {
    func convert(animation: GLTFAnimation) throws -> AnimationResource {
        var groupedChannels = [UUID: [GLTFAnimationChannel]]()
        for channel in animation.channels {
            guard let id = channel.target.node?.identifier else { continue }
            groupedChannels[id, default: []].append(channel)
        }
        let name = animation.name ?? nextUniqueName(prefix: "Animation")

        struct AnimatedJointData {
            var jointNames = [String]()
            var jointTransformSamplers = [TransformSampler]()
            var minTime: Float = 0
            var maxTime: Float = 0
            var sampleInterval: Float = 1 / 30.0
        }
        var jointAnimation = AnimatedJointData()
        var animations = [AnimationDefinition]()
        for (_, channels) in groupedChannels {
            guard let targetNode = channels.first?.target.node else {
                continue // Can't create an animation without at least one channel and a target
            }
            if let weightsChannel = channels.first(where: { $0.target.path == GLTFAnimationPath.weights.rawValue }),
               let morphAnimation = convertMorphWeights(channel: weightsChannel, target: targetNode)
            {
                animations.append(morphAnimation)
            }
            if channels.allSatisfy({ $0.target.path == GLTFAnimationPath.weights.rawValue }) {
                continue
            }
            let translationChannel = channels.first { $0.target.path == GLTFAnimationPath.translation.rawValue }
            let rotationChannel = channels.first { $0.target.path == GLTFAnimationPath.rotation.rawValue }
            let scaleChannel = channels.first { $0.target.path == GLTFAnimationPath.scale.rawValue }
            let transformSampler = TransformSampler(target: targetNode,
                                                        translationChannel: translationChannel,
                                                        rotationChannel: rotationChannel,
                                                        scaleChannel: scaleChannel,
                                                        maximumSampleInterval: 1 / 30.0) // TODO: Make sample interval an option
            if targetNode.isJoint {
                let jointName: String
                if let index = Skin.jointIndex(of: targetNode, in: sourceAsset?.skins ?? []) {
                    jointName = Skin.resolvedName(targetNode.name, index: index)
                } else if let name = targetNode.name, !name.isEmpty {
                    jointName = name
                } else {
                    jointName = nextUniqueName(prefix: "joint")
                }
                jointAnimation.jointNames.append(jointName)
                jointAnimation.jointTransformSamplers.append(transformSampler)
                jointAnimation.minTime = min(jointAnimation.minTime, transformSampler.startTime)
                jointAnimation.maxTime = max(jointAnimation.maxTime, transformSampler.endTime)
                jointAnimation.sampleInterval = min(jointAnimation.sampleInterval, transformSampler.recommendedSampleInterval)
            } else {
                let frames = stride(from: transformSampler.startTime,
                                    through: transformSampler.endTime,
                                    by: transformSampler.recommendedSampleInterval).map
                {
                    transformSampler.transform(at: $0)
                }
                let sampledAnimation = SampledAnimation(frames: frames,
                                                        tweenMode: transformSampler.hasStepChannel ? .hold : .linear,
                                                        frameInterval: transformSampler.recommendedSampleInterval,
                                                        bindTarget: targetNode.bindPath.transform,
                                                        delay: TimeInterval(transformSampler.startTime))
                animations.append(sampledAnimation)
            }
        }
        if !jointAnimation.jointNames.isEmpty {
            var jointTransforms = [JointTransforms]()
            for t in stride(from: jointAnimation.minTime, through: jointAnimation.maxTime, by: jointAnimation.sampleInterval) {
                let sampledTransforms = zip(jointAnimation.jointNames, jointAnimation.jointTransformSamplers).map { jointName, transformSampler -> Transform in
                    var jointTransform = transformSampler.transform(at: t)
                    if let ancestorTransform = skeletonTransformsByJointName[jointName] {
                        jointTransform = Transform(matrix: ancestorTransform.matrix * jointTransform.matrix)
                    }
                    return jointTransform
                }
                jointTransforms.append(JointTransforms(sampledTransforms))
            }
            let delay = TimeInterval(jointAnimation.minTime)

            var animatedSkeletonIDs = Set</*MeshResource.Skeleton.ID*/String>()
            for jointName in jointAnimation.jointNames {
                if let skeletonIDs = skeletonIDsByJointName[jointName] {
                    animatedSkeletonIDs.formUnion(skeletonIDs)
                }
            }
            let animatedBindPaths = animatedSkeletonIDs.compactMap { pathsForSkeletonIDs[$0] }
            for bindPath in animatedBindPaths {
                let skeletalAnimation = SampledAnimation(jointNames: jointAnimation.jointNames,
                                                         frames: jointTransforms,
                                                         tweenMode: .linear, // TODO: Support .hold?
                                                         frameInterval: jointAnimation.sampleInterval,
                                                         bindTarget: bindPath.jointTransforms,
                                                         delay: delay)
                animations.append(skeletalAnimation)
            }
        }

        if animations.isEmpty {
            throw GLBPreviewError.make(1022, "animation \(name) produced no channels")
        }
        if animations.count == 1 {
            return try AnimationResource.generate(with: animations[0])
        }
        let groupAnimation = AnimationGroup(group: animations, name: name)
        return try AnimationResource.generate(with: groupAnimation)
    }

    private func convertMorphWeights(channel: GLTFAnimationChannel, target: GLTFNode) -> AnimationDefinition? {
        guard let mesh = target.mesh else { return nil }
        let names = morphTargetNames(for: mesh)
        guard !names.isEmpty,
              let times = Packed.floatArray(for: channel.sampler.input),
              let values = Packed.floatArray(for: channel.sampler.output),
              !times.isEmpty
        else { return nil }
        let sampler = AnimatedWeights(
            keyTimes: times,
            values: values,
            targetCount: names.count,
            interpolation: channel.sampler.interpolationMode
        )
        let interval = max(sampler.recommendedSampleInterval, 1 / 60)
        let frames = stride(from: sampler.minimumTime, through: sampler.maximumTime, by: interval).map {
            BlendShapeWeights(sampler.value(at: $0))
        }
        return SampledAnimation(
            weightNames: names,
            frames: frames,
            tweenMode: sampler.interpolation == .step ? .hold : .linear,
            frameInterval: interval,
            bindTarget: target.bindPath.blendShapeWeights(),
            delay: TimeInterval(sampler.minimumTime)
        )
    }
}
