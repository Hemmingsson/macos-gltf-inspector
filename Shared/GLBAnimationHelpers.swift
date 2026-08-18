// Vendored from warrenm/GLTFKit2 impl/GLTFAnimationHelpers.swift (MIT).
// The xcframework does not export these types.

import GLTFKit2
import RealityKit
import simd

func glbLerp(_ a: simd_float3, _ b: simd_float3, _ t: Float) -> simd_float3 {
    a + t * (b - a)
}

func glbUnlerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    if a == b { return 0 }
    return (t - a) / (b - a)
}

func glbCubicInterp(
    _ a: SIMD3<Float>,
    _ b: SIMD3<Float>,
    _ inTangent: SIMD3<Float>,
    _ outTangent: SIMD3<Float>,
    _ t: Float,
    _ dT: Float
) -> SIMD3<Float> {
    let t2 = t * t
    let t3 = t2 * t
    return (2 * t3 - 3 * t2 + 1) * a
        + dT * (t3 - 2 * t2 + t) * inTangent
        + (-2 * t3 + 3 * t2) * b
        + dT * (t3 - t2) * outTangent
}

protocol GLBAnimatedValue {
    var sampleCount: Int { get }
    var minimumTime: Float { get }
    var maximumTime: Float { get }
    var interpolation: GLTFInterpolationMode { get }
    var keyTimes: [Float] { get }
}

extension GLBAnimatedValue {
    var sampleCount: Int { keyTimes.count }
    var minimumTime: Float { keyTimes.first ?? 0 }
    var maximumTime: Float { keyTimes.last ?? 0 }

    func keyTimeIndicesForTime(_ time: Float) -> (index: Int, nextIndex: Int)? {
        guard !keyTimes.isEmpty else { return nil }
        if time <= keyTimes[0] {
            return keyTimes.count > 1 ? (0, 1) : (0, 0)
        }
        if time >= keyTimes[keyTimes.count - 1] {
            let lastIndex = keyTimes.count - 1
            return lastIndex > 0 ? (lastIndex - 1, lastIndex) : (lastIndex, lastIndex)
        }
        var low = 0
        var high = keyTimes.count - 1
        while low < high - 1 {
            let mid = (low + high) / 2
            if keyTimes[mid] <= time {
                low = mid
            } else {
                high = mid
            }
        }
        return (low, high)
    }
}

final class GLBAnimatedVector3: GLBAnimatedValue {
    let keyTimes: [Float]
    let values: [SIMD3<Float>]
    let interpolation: GLTFInterpolationMode

    init(keyTimes: [Float], values: [SIMD3<Float>], interpolation: GLTFInterpolationMode) {
        self.keyTimes = keyTimes
        self.values = values
        self.interpolation = interpolation
    }

    func value(at time: Float) -> SIMD3<Float> {
        guard !values.isEmpty else { return .zero }
        guard let (index, nextIndex) = keyTimeIndicesForTime(time) else {
            return values[0]
        }
        if index == nextIndex {
            return values[index]
        }
        let t0 = keyTimes[index]
        let t1 = keyTimes[nextIndex]
        let factor = glbUnlerp(t0, t1, time)
        switch interpolation {
        case .step:
            return values[index]
        case .cubic:
            return glbCubicInterp(
                values[index * 3 + 1],
                values[nextIndex * 3 + 1],
                values[index * 3 + 2],
                values[nextIndex * 3 + 0],
                factor,
                t1 - t0
            )
        default:
            return glbLerp(values[index], values[nextIndex], factor)
        }
    }
}

final class GLBAnimatedQuaternion: GLBAnimatedValue {
    let keyTimes: [Float]
    let values: [simd_quatf]
    let interpolation: GLTFInterpolationMode

    init(keyTimes: [Float], values: [simd_quatf], interpolation: GLTFInterpolationMode) {
        self.keyTimes = keyTimes
        self.values = values
        self.interpolation = interpolation
    }

    func value(at time: Float) -> simd_quatf {
        guard !values.isEmpty else { return simd_quatf() }
        guard let (index, nextIndex) = keyTimeIndicesForTime(time) else {
            return values[0]
        }
        if index == nextIndex {
            return values[index]
        }
        let t0 = keyTimes[index]
        let t1 = keyTimes[nextIndex]
        let factor = glbUnlerp(t0, t1, time)
        switch interpolation {
        case .step:
            return values[index]
        case .cubic:
            return simd_slerp(values[index * 3 + 1], values[nextIndex * 3 + 1], factor)
        default:
            return simd_slerp(values[index], values[nextIndex], factor)
        }
    }
}

final class GLBTransformSampler {
    let startTime: Float
    let endTime: Float
    let recommendedSampleInterval: Float
    let translation: GLBAnimatedVector3
    let rotation: GLBAnimatedQuaternion
    let scale: GLBAnimatedVector3
    let hasStepChannel: Bool

    init(
        target: GLTFNode,
        translationChannel: GLTFAnimationChannel?,
        rotationChannel: GLTFAnimationChannel?,
        scaleChannel: GLTFAnimationChannel?,
        maximumSampleInterval: Float
    ) {
        var minTime: Float = .infinity
        var maxTime: Float = -.infinity
        for channel in [translationChannel, rotationChannel, scaleChannel] {
            if let input = channel?.sampler.input {
                let channelMinTime = input.minValues.first?.floatValue ?? .infinity
                let channelMaxTime = input.maxValues.first?.floatValue ?? -.infinity
                minTime = min(minTime, channelMinTime)
                maxTime = max(maxTime, channelMaxTime)
            }
        }

        var translationTimes = [minTime]
        var translationValues = [target.translation]
        var translationInterp = GLTFInterpolationMode.linear
        if let sampler = translationChannel?.sampler,
           let times = GLBPacked.floatArray(for: sampler.input),
           let values = GLBPacked.float3Array(for: sampler.output)
        {
            translationTimes = times
            translationValues = values
            translationInterp = sampler.interpolationMode
        }

        var rotationTimes = [minTime]
        var rotationValues = [target.rotation]
        var rotationInterp = GLTFInterpolationMode.linear
        if let sampler = rotationChannel?.sampler,
           let times = GLBPacked.floatArray(for: sampler.input),
           let values = GLBPacked.quatfArray(for: sampler.output)
        {
            rotationTimes = times
            rotationValues = values
            rotationInterp = sampler.interpolationMode
        }

        var scaleTimes = [minTime]
        var scaleValues = [target.scale]
        var scaleInterp = GLTFInterpolationMode.linear
        if let sampler = scaleChannel?.sampler,
           let times = GLBPacked.floatArray(for: sampler.input),
           let values = GLBPacked.float3Array(for: sampler.output)
        {
            scaleTimes = times
            scaleValues = values
            scaleInterp = sampler.interpolationMode
        }

        startTime = minTime
        endTime = maxTime
        hasStepChannel = translationInterp == .step || rotationInterp == .step || scaleInterp == .step
        translation = GLBAnimatedVector3(
            keyTimes: translationTimes,
            values: translationValues,
            interpolation: translationInterp
        )
        rotation = GLBAnimatedQuaternion(
            keyTimes: rotationTimes,
            values: rotationValues,
            interpolation: rotationInterp
        )
        scale = GLBAnimatedVector3(
            keyTimes: scaleTimes,
            values: scaleValues,
            interpolation: scaleInterp
        )
        let duration = maxTime - minTime
        let keyCount = max(translationTimes.count, max(rotationTimes.count, scaleTimes.count))
        let averageKeyDuration = duration / Float(max(keyCount, 1))
        recommendedSampleInterval = averageKeyDuration > maximumSampleInterval
            ? maximumSampleInterval
            : averageKeyDuration
    }

    func transform(at time: Float) -> Transform {
        Transform(
            scale: scale.value(at: time),
            rotation: rotation.value(at: time),
            translation: translation.value(at: time)
        )
    }
}
