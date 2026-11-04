import Foundation
import simd
import Testing
@testable import Renderer

struct AnimationSamplerTests {
    private func scalarSampler(
        input: [Float],
        values: [Float],
        interpolation: AnimationInterpolation,
        clipMaxTime: Float,
        isRotation: Bool = false
    ) -> AnimationSampler {
        AnimationSampler(
            input: input,
            output: values,
            componentCount: 1,
            interpolation: interpolation,
            clipMaxTime: clipMaxTime,
            isRotation: isRotation
        )
    }

    @Test func stepAndLinearBetweenTwoScalarKeys() {
        let sampler = scalarSampler(input: [0, 2], values: [0, 4], interpolation: .step, clipMaxTime: 2)
        let linear = scalarSampler(input: [0, 2], values: [0, 4], interpolation: .linear, clipMaxTime: 2)
        #expect(sampler.evaluate(at: 1)[0] == 0)
        #expect(abs(linear.evaluate(at: 1)[0] - 2) < 1e-6)
    }

    @Test func scalarEndpointsAndSingleKey() {
        let twoKey = scalarSampler(input: [0, 2], values: [0, 4], interpolation: .linear, clipMaxTime: 2)
        #expect(twoKey.evaluate(at: 0)[0] == 0)
        #expect(twoKey.evaluate(at: 2)[0] == 4)

        let oneKey = scalarSampler(input: [1.5], values: [7], interpolation: .linear, clipMaxTime: 4)
        #expect(oneKey.evaluate(at: 0)[0] == 7)
        #expect(oneKey.evaluate(at: 99)[0] == 7)
    }

    @Test func cubicSplineScalesTangentsByKeyGap() {
        // Keys at t=0 and t=3; independent Hermite at t=1.5 → 4.5 when tangents are × keyDelta.
        let output: [Float] = [
            0, 0, 1, // key 0: in, value, out tangent
            1, 9, 1, // key 1
        ]
        let sampler = AnimationSampler(
            input: [0, 3],
            output: output,
            componentCount: 1,
            interpolation: .cubicSpline,
            clipMaxTime: 3,
            isRotation: false
        )
        #expect(abs(sampler.evaluate(at: 1.5)[0] - 4.5) < 1e-5)
        // Wrong scaling (tangents without × gap) would land near 2.25 at tn=0.5.
        #expect(abs(sampler.evaluate(at: 1.5)[0] - 2.25) > 0.5)
    }

    @Test func cubicQuaternionIsNormalized() {
        let identity: [Float] = [0, 0, 0, 1]
        let output: [Float] = identity + [0, 0, 0, 0] + [0, 0, 0, 0]
            + identity + [0, 0, 0, 0] + [0, 0, 0, 0]
        let sampler = AnimationSampler(
            input: [0, 1],
            output: output,
            componentCount: 4,
            interpolation: .cubicSpline,
            clipMaxTime: 1,
            isRotation: true
        )
        let q = sampler.evaluate(at: 0.5)
        let len = sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
        #expect(abs(len - 1) < 1e-5)
    }

    @Test func quaternionShortestPathAndNearEqual() {
        let q: [Float] = [0, 0, 0, 1]
        let minusQ: [Float] = [0, 0, 0, -1]
        let linear = AnimationSampler(
            input: [0, 1],
            output: q + minusQ,
            componentCount: 4,
            interpolation: .linear,
            clipMaxTime: 1,
            isRotation: true
        )
        let mid = linear.evaluate(at: 0.5)
        #expect(abs(mid[3]) > 0.99)
        #expect(abs(mid[0]) + abs(mid[1]) + abs(mid[2]) < 1e-4)

        let a: [Float] = [0, 0, 0, 1]
        let b: [Float] = [0, 0, 0.00001, 0.99999995]
        let near = AnimationSampler(
            input: [0, 1],
            output: a + b,
            componentCount: 4,
            interpolation: .linear,
            clipMaxTime: 1,
            isRotation: true
        )
        let blended = near.evaluate(at: 0.5)
        let blendedLen = sqrt(blended.map { $0 * $0 }.reduce(0, +))
        #expect(abs(blendedLen - 1) < 1e-5)
        #expect(!blended.contains { $0.isNaN })
    }

    @Test func wrapClampNegativePastEndAndMaxTime() {
        let sampler = scalarSampler(input: [0, 2], values: [0, 4], interpolation: .linear, clipMaxTime: 4)
        // Negative time wraps: -1 % 4 → -1, +4 → 3, clamp to 2 → last key value 4.
        #expect(abs(sampler.evaluate(at: -1)[0] - 4) < 1e-5)
        // Past clip end: 5 % 4 = 1 → interpolate at 1 → 2.
        #expect(abs(sampler.evaluate(at: 5)[0] - 2) < 1e-5)
        // Exactly maxTime: 4 % 4 = 0, add 4 → 4, clamp to 2 → endpoint 4.
        #expect(abs(sampler.evaluate(at: 4)[0] - 4) < 1e-5)
    }

    @Test func channelShorterThanClipHoldsLastKey() {
        // Clip loops with max 10; channel only spans [0, 2].
        let sampler = scalarSampler(input: [0, 2], values: [0, 4], interpolation: .linear, clipMaxTime: 10)
        // t=7 → 7 % 10 = 7, clamp to 2 → value at last key 4.
        #expect(abs(sampler.evaluate(at: 7)[0] - 4) < 1e-5)
    }
}
