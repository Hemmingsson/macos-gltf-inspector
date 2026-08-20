// Vendored from warrenm/GLTFKit2 impl/GLTFAnimationHelpers.swift (MIT).
// The xcframework does not export these types.

import GLTFKit2
import RealityKit
import simd

enum AnimationSampling {
    static let defaultInterval: Float = 1 / 30
    static let minimumInterval: Float = 1 / 120
    static let minimumDuration: Float = 1e-4

    static func sampleInterval(averageKeyDuration: Float, maximum: Float) -> Float {
        let cap = maximum.isFinite && maximum > 0 ? maximum : defaultInterval
        if !averageKeyDuration.isFinite || averageKeyDuration <= 0 {
            return min(cap, defaultInterval)
        }
        return min(max(averageKeyDuration, minimumInterval), cap)
    }

    static func mergeSampleInterval(_ current: Float, _ candidate: Float) -> Float {
        let safeCurrent = sampleInterval(averageKeyDuration: current, maximum: defaultInterval)
        guard candidate.isFinite, candidate > 0 else { return safeCurrent }
        return min(safeCurrent, sampleInterval(averageKeyDuration: candidate, maximum: defaultInterval))
    }

    static func sampleTimes(from start: Float, through end: Float, by interval: Float) -> [Float] {
        let step = sampleInterval(averageKeyDuration: interval, maximum: defaultInterval)
        let lo = start.isFinite ? start : 0
        let hi = end.isFinite ? max(end, lo) : lo
        return Array(stride(from: lo, through: hi, by: step))
    }

    static func frameInterval(_ interval: Float) -> Float {
        sampleInterval(averageKeyDuration: interval, maximum: defaultInterval)
    }

    static func inputRange(of sampler: GLTFAnimationSampler) -> (count: Int, minTime: Float, maxTime: Float) {
        var minTime = Float.infinity
        var maxTime = -Float.infinity
        if let lo = sampler.input.minValues.first?.floatValue, lo.isFinite {
            minTime = min(minTime, lo)
        }
        if let hi = sampler.input.maxValues.first?.floatValue, hi.isFinite {
            maxTime = max(maxTime, hi)
        }
        if let times = Packed.floatArray(for: sampler.input) {
            if let first = times.first, first.isFinite { minTime = min(minTime, first) }
            if let last = times.last, last.isFinite { maxTime = max(maxTime, last) }
            return (max(times.count, sampler.input.count), minTime, maxTime)
        }
        return (sampler.input.count, minTime, maxTime)
    }

    static func hasPositiveDuration(_ animation: GLTFAnimation) -> Bool {
        var minTime = Float.infinity
        var maxTime = -Float.infinity
        var sampleCount = 0
        for sampler in animation.samplers {
            let range = inputRange(of: sampler)
            sampleCount = max(sampleCount, range.count)
            if range.minTime.isFinite { minTime = min(minTime, range.minTime) }
            if range.maxTime.isFinite { maxTime = max(maxTime, range.maxTime) }
        }
        guard minTime.isFinite, maxTime.isFinite else { return false }
        return sampleCount > 1 && maxTime - minTime > minimumDuration
    }

    static func documentedDuration(_ animation: GLTFAnimation) -> Double {
        var maxTime: Float = 0
        for sampler in animation.samplers {
            let hi = inputRange(of: sampler).maxTime
            if hi.isFinite { maxTime = max(maxTime, hi) }
        }
        return Double(max(maxTime, 0))
    }
}

private extension Array {
    subscript(checked index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

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

protocol AnimatedValue {
    var sampleCount: Int { get }
    var minimumTime: Float { get }
    var maximumTime: Float { get }
    var interpolation: GLTFInterpolationMode { get }
    var keyTimes: [Float] { get }
}

extension AnimatedValue {
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

final class AnimatedVector3: AnimatedValue {
    let keyTimes: [Float]
    let values: [SIMD3<Float>]
    let interpolation: GLTFInterpolationMode

    init(keyTimes: [Float], values: [SIMD3<Float>], interpolation: GLTFInterpolationMode) {
        self.keyTimes = keyTimes
        self.values = values
        self.interpolation = interpolation
    }

    func value(at time: Float) -> SIMD3<Float> {
        guard let (index, nextIndex) = keyTimeIndicesForTime(time) else {
            return values.first ?? .zero
        }
        if index == nextIndex || interpolation == .step {
            return values[checked: index] ?? values.first ?? .zero
        }
        let t0 = keyTimes[index]
        let t1 = keyTimes[nextIndex]
        let factor = glbUnlerp(t0, t1, time)
        if interpolation == .cubic,
           let a = values[checked: index * 3 + 1],
           let b = values[checked: nextIndex * 3 + 1],
           let outTangent = values[checked: index * 3 + 2],
           let inTangent = values[checked: nextIndex * 3]
        {
            return glbCubicInterp(a, b, inTangent, outTangent, factor, t1 - t0)
        }
        let a = values[checked: index] ?? values.first ?? .zero
        let b = values[checked: nextIndex] ?? a
        return glbLerp(a, b, factor)
    }
}

final class AnimatedQuaternion: AnimatedValue {
    let keyTimes: [Float]
    let values: [simd_quatf]
    let interpolation: GLTFInterpolationMode

    init(keyTimes: [Float], values: [simd_quatf], interpolation: GLTFInterpolationMode) {
        self.keyTimes = keyTimes
        self.values = values
        self.interpolation = interpolation
    }

    func value(at time: Float) -> simd_quatf {
        let identity = simd_quatf()
        guard let (index, nextIndex) = keyTimeIndicesForTime(time) else {
            return values.first ?? identity
        }
        if index == nextIndex || interpolation == .step {
            return values[checked: index] ?? values.first ?? identity
        }
        let t0 = keyTimes[index]
        let t1 = keyTimes[nextIndex]
        let factor = glbUnlerp(t0, t1, time)
        if interpolation == .cubic,
           let a = values[checked: index * 3 + 1],
           let b = values[checked: nextIndex * 3 + 1]
        {
            return simd_slerp(a, b, factor)
        }
        let a = values[checked: index] ?? values.first ?? identity
        let b = values[checked: nextIndex] ?? a
        return simd_slerp(a, b, factor)
    }
}

final class AnimatedWeights: AnimatedValue {
    let keyTimes: [Float]
    let values: [Float]
    let targetCount: Int
    let interpolation: GLTFInterpolationMode

    init(keyTimes: [Float], values: [Float], targetCount: Int, interpolation: GLTFInterpolationMode) {
        self.keyTimes = keyTimes
        self.values = values
        self.targetCount = max(targetCount, 1)
        self.interpolation = interpolation
    }

    var recommendedSampleInterval: Float {
        let duration = max((maximumTime.isFinite ? maximumTime : 0) - (minimumTime.isFinite ? minimumTime : 0), 0)
        let average = duration / Float(max(keyTimes.count, 1))
        return AnimationSampling.sampleInterval(averageKeyDuration: average, maximum: AnimationSampling.defaultInterval)
    }

    func value(at time: Float) -> [Float] {
        guard !values.isEmpty else { return [Float](repeating: 0, count: targetCount) }
        guard let (index, nextIndex) = keyTimeIndicesForTime(time) else {
            return weights(atKeyframe: 0)
        }
        if interpolation == .step || index == nextIndex {
            return weights(atKeyframe: index)
        }
        let t0 = keyTimes[index]
        let t1 = keyTimes[nextIndex]
        let factor = glbUnlerp(t0, t1, time)
        return zip(weights(atKeyframe: index), weights(atKeyframe: nextIndex)).map {
            $0 + factor * ($1 - $0)
        }
    }

    private func weights(atKeyframe keyframe: Int) -> [Float] {
        let stride = interpolation == .cubic ? targetCount * 3 : targetCount
        let valueOffset = interpolation == .cubic ? targetCount : 0
        let base = keyframe * stride + valueOffset
        guard base >= 0, base + targetCount <= values.count else {
            return [Float](repeating: 0, count: targetCount)
        }
        return Array(values[base..<(base + targetCount)])
    }
}

final class TransformSampler {
    let startTime: Float
    let endTime: Float
    let recommendedSampleInterval: Float
    let translation: AnimatedVector3
    let rotation: AnimatedQuaternion
    let scale: AnimatedVector3
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
            guard let sampler = channel?.sampler else { continue }
            let range = AnimationSampling.inputRange(of: sampler)
            if range.minTime.isFinite { minTime = min(minTime, range.minTime) }
            if range.maxTime.isFinite { maxTime = max(maxTime, range.maxTime) }
        }
        let seedTime = minTime.isFinite ? minTime : 0

        var translationTimes = [seedTime]
        var translationValues = [target.translation]
        var translationInterp = GLTFInterpolationMode.linear
        if let sampler = translationChannel?.sampler,
           let times = Packed.floatArray(for: sampler.input),
           let values = Packed.float3Array(for: sampler.output)
        {
            translationTimes = times
            translationValues = values
            translationInterp = sampler.interpolationMode
            if let first = times.first { minTime = min(minTime, first) }
            if let last = times.last { maxTime = max(maxTime, last) }
        }

        var rotationTimes = [seedTime]
        var rotationValues = [target.rotation]
        var rotationInterp = GLTFInterpolationMode.linear
        if let sampler = rotationChannel?.sampler,
           let times = Packed.floatArray(for: sampler.input),
           let values = Packed.quatfArray(for: sampler.output)
        {
            rotationTimes = times
            rotationValues = values
            rotationInterp = sampler.interpolationMode
            if let first = times.first { minTime = min(minTime, first) }
            if let last = times.last { maxTime = max(maxTime, last) }
        }

        var scaleTimes = [seedTime]
        var scaleValues = [target.scale]
        var scaleInterp = GLTFInterpolationMode.linear
        if let sampler = scaleChannel?.sampler,
           let times = Packed.floatArray(for: sampler.input),
           let values = Packed.float3Array(for: sampler.output)
        {
            scaleTimes = times
            scaleValues = values
            scaleInterp = sampler.interpolationMode
            if let first = times.first { minTime = min(minTime, first) }
            if let last = times.last { maxTime = max(maxTime, last) }
        }

        if !minTime.isFinite { minTime = 0 }
        if !maxTime.isFinite { maxTime = minTime }
        if maxTime < minTime { maxTime = minTime }

        startTime = minTime
        endTime = maxTime
        hasStepChannel = translationInterp == .step || rotationInterp == .step || scaleInterp == .step
        translation = AnimatedVector3(
            keyTimes: translationTimes,
            values: translationValues,
            interpolation: translationInterp
        )
        rotation = AnimatedQuaternion(
            keyTimes: rotationTimes,
            values: rotationValues,
            interpolation: rotationInterp
        )
        scale = AnimatedVector3(
            keyTimes: scaleTimes,
            values: scaleValues,
            interpolation: scaleInterp
        )
        let duration = max(maxTime - minTime, 0)
        let keyCount = max(translationTimes.count, max(rotationTimes.count, scaleTimes.count))
        let averageKeyDuration = duration / Float(max(keyCount, 1))
        recommendedSampleInterval = AnimationSampling.sampleInterval(
            averageKeyDuration: averageKeyDuration,
            maximum: maximumSampleInterval
        )
    }

    func transform(at time: Float) -> Transform {
        Transform(
            scale: scale.value(at: time),
            rotation: rotation.value(at: time),
            translation: translation.value(at: time)
        )
    }
}
