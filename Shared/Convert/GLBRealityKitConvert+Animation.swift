import RealityKit
import GLTFKit2

extension GLBRealityKitConvert {
    func convert(animation: GLTFAnimation) throws -> AnimationResource {
        let groupedChannels = animation.channels.reduce(into: [UUID : [GLTFAnimationChannel]]()) { partialResult, channel in
            guard let targetIdentifier = channel.target.node?.identifier else { return }
            if let _ = partialResult[targetIdentifier] {
                partialResult[targetIdentifier]! += [channel]
            } else {
                partialResult[targetIdentifier] = [channel]
            }
        }
        let name = animation.name ?? nextUniqueName(prefix: "Animation")

        struct AnimatedJointData {
            var jointNames = [String]()
            var jointTransformSamplers = [GLBTransformSampler]()
            var minTime: Float = 0
            var maxTime: Float = 0
            var sampleInterval: Float = 1 / 30.0
        }
        var jointAnimation = AnimatedJointData()
        var animations = [AnimationDefinition]()
        for (_, channels) in groupedChannels {
            if let _ = channels.first(where: { $0.target.path == GLTFAnimationPath.weights.rawValue }), channels.count == 1 {
                continue // TODO: Implement morph target animation
            }
            guard let targetNode = channels.first?.target.node else {
                continue // Can't create an animation without at least one channel and a target
            }
            let translationChannel = channels.first { $0.target.path == GLTFAnimationPath.translation.rawValue }
            let rotationChannel = channels.first { $0.target.path == GLTFAnimationPath.rotation.rawValue }
            let scaleChannel = channels.first { $0.target.path == GLTFAnimationPath.scale.rawValue }
            let transformSampler = GLBTransformSampler(target: targetNode,
                                                        translationChannel: translationChannel,
                                                        rotationChannel: rotationChannel,
                                                        scaleChannel: scaleChannel,
                                                        maximumSampleInterval: 1 / 30.0) // TODO: Make sample interval an option
            if targetNode.isJoint {
                let jointName: String
                if let name = targetNode.name, !name.isEmpty {
                    jointName = name
                } else if let index = GLBSkin.jointIndex(of: targetNode, in: sourceAsset?.skins ?? []) {
                    jointName = GLBSkin.synthesizedName(index: index)
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

        let groupAnimation = AnimationGroup(group: animations, name: name)
        return try AnimationResource.generate(with: groupAnimation)
    }
}
