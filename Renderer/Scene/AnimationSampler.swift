import Foundation
import simd

/// glTF animation sampler interpolation modes (`animation.sampler.interpolation`).
public enum AnimationInterpolation: Sendable, Equatable {
    case step
    case linear
    case cubicSpline
}

/// Evaluates one glTF animation channel at time *t*, matching Khronos wrap, clamp, and interpolation.
public struct AnimationSampler: Sendable {
    public let input: [Float]
    public let output: [Float]
    public let componentCount: Int
    public let interpolation: AnimationInterpolation
    /// Clip-wide maximum time used for looping before clamping to this channel's key range.
    public let clipMaxTime: Float
    /// When true, LINEAR and CUBICSPLINE treat four-component keys as quaternions (slerp / normalize).
    public let isRotation: Bool

    public init(
        input: [Float],
        output: [Float],
        componentCount: Int,
        interpolation: AnimationInterpolation,
        clipMaxTime: Float,
        isRotation: Bool = false
    ) {
        self.input = input
        self.output = output
        self.componentCount = componentCount
        self.interpolation = interpolation
        self.clipMaxTime = clipMaxTime
        self.isRotation = isRotation
    }

    /// Samples the channel at `rawTime` (seconds in clip time, before wrap).
    public func evaluate(at rawTime: Float, wraps: Bool = true) -> [Float] {
        guard !input.isEmpty, componentCount > 0 else { return [] }

        let valueStride = outputStride
        if input.count == 1 {
            return singleKeyValue()
        }
        precondition(output.count == input.count * valueStride, "output count must match key count × stride")

        let t = wraps ? wrappedAndClampedTime(rawTime) : clampedTime(rawTime)
        let nextKey = nextKeyframeIndex(for: t)
        let prevKey = nextKey - 1
        let tPrev = input[prevKey]
        let tNext = input[nextKey]
        let tn: Float = tNext > tPrev ? (t - tPrev) / (tNext - tPrev) : 0

        switch interpolation {
        case .step:
            return copyValue(atKey: prevKey)
        case .linear:
            let a = copyValue(atKey: prevKey)
            let b = copyValue(atKey: nextKey)
            return interpolateLinear(from: a, to: b, tn: tn, normalizeRotation: isRotation)
        case .cubicSpline:
            let a = copyValue(atKey: prevKey)
            let b = copyValue(atKey: nextKey)
            let outTan = copyOutTangent(atKey: prevKey)
            let inTan = copyInTangent(atKey: nextKey)
            let keyDelta = tNext - tPrev
            return interpolateCubic(
                from: a,
                to: b,
                outTangent: outTan,
                inTangent: inTan,
                keyDelta: keyDelta,
                tn: tn,
                normalizeRotation: isRotation
            )
        }
    }

    private var outputStride: Int {
        switch interpolation {
        case .step, .linear:
            return componentCount
        case .cubicSpline:
            return componentCount * 3
        }
    }

    private func singleKeyValue() -> [Float] {
        switch interpolation {
        case .step, .linear:
            return Array(output.prefix(componentCount))
        case .cubicSpline:
            return Array(output[componentCount ..< (2 * componentCount)])
        }
    }

    private func wrappedAndClampedTime(_ rawTime: Float) -> Float {
        let maxTime = clipMaxTime
        guard maxTime > 0, !input.isEmpty else { return input.first ?? 0 }

        var t = rawTime.truncatingRemainder(dividingBy: maxTime)
        if t < 0 || (t == 0 && rawTime != 0) {
            t += maxTime
        }
        return clampedTime(t)
    }

    private func clampedTime(_ rawTime: Float) -> Float {
        guard !input.isEmpty else { return 0 }
        let first = input[0]
        let last = input[input.count - 1]
        return min(max(rawTime, first), last)
    }

    private func nextKeyframeIndex(for t: Float) -> Int {
        var nextKey = 0
        for i in 0 ..< input.count where t <= input[i] {
            nextKey = i
            break
        }
        if nextKey < 1 {
            nextKey = 1
        }
        return nextKey
    }

    private func copyValue(atKey key: Int) -> [Float] {
        let base = key * outputStride
        switch interpolation {
        case .step, .linear:
            return Array(output[base ..< (base + componentCount)])
        case .cubicSpline:
            return Array(output[(base + componentCount) ..< (base + 2 * componentCount)])
        }
    }

    private func copyOutTangent(atKey key: Int) -> [Float] {
        let base = key * outputStride
        return Array(output[(base + 2 * componentCount) ..< (base + 3 * componentCount)])
    }

    private func copyInTangent(atKey key: Int) -> [Float] {
        let base = key * outputStride
        return Array(output[base ..< (base + componentCount)])
    }

    private func interpolateLinear(
        from a: [Float],
        to b: [Float],
        tn: Float,
        normalizeRotation: Bool
    ) -> [Float] {
        if normalizeRotation, componentCount == 4 {
            let q = slerpQuaternions(a, b, tn: tn)
            return [q.x, q.y, q.z, q.w]
        }
        return zip(a, b).map { $0 + tn * ($1 - $0) }
    }

    private func interpolateCubic(
        from a: [Float],
        to b: [Float],
        outTangent: [Float],
        inTangent: [Float],
        keyDelta: Float,
        tn: Float,
        normalizeRotation: Bool
    ) -> [Float] {
        let t2 = tn * tn
        let t3 = t2 * tn
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + tn
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        var result = [Float]()
        result.reserveCapacity(componentCount)
        for i in 0 ..< componentCount {
            let m0 = outTangent[i] * keyDelta
            let m1 = inTangent[i] * keyDelta
            let v = h00 * a[i] + h10 * m0 + h01 * b[i] + h11 * m1
            result.append(v)
        }

        if normalizeRotation, componentCount == 4 {
            let q = simd_normalize(SIMD4(result[0], result[1], result[2], result[3]))
            return [q.x, q.y, q.z, q.w]
        }
        return result
    }

    private func slerpQuaternions(_ a: [Float], _ b: [Float], tn: Float) -> SIMD4<Float> {
        var q0 = simd_normalize(SIMD4(a[0], a[1], a[2], a[3]))
        var q1 = simd_normalize(SIMD4(b[0], b[1], b[2], b[3]))
        var dot = simd_dot(q0, q1)
        if dot < 0 {
            q1 = -q1
            dot = -dot
        }
        if 1 - dot <= 1e-6 {
            return simd_normalize(q0 + tn * (q1 - q0))
        }
        let theta = acos(min(1, dot))
        let sinTheta = sin(theta)
        let w0 = sin((1 - tn) * theta) / sinTheta
        let w1 = sin(tn * theta) / sinTheta
        return simd_normalize(w0 * q0 + w1 * q1)
    }
}
