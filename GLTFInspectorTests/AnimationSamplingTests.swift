import Foundation
import RealityKit
import Testing
@testable import GLTFInspector

struct AnimationSamplingTests {
    @Test func clampsZeroAndNonFiniteIntervals() {
        #expect(AnimationSampling.sampleInterval(averageKeyDuration: 0, maximum: 1 / 30) > 0)
        #expect(AnimationSampling.sampleInterval(averageKeyDuration: .nan, maximum: 1 / 30) > 0)
        #expect(AnimationSampling.sampleInterval(averageKeyDuration: -.infinity, maximum: 1 / 30) > 0)
        let thirty: Float = 1 / 30
        #expect(AnimationSampling.mergeSampleInterval(thirty, 0) > 0)
        #expect(AnimationSampling.mergeSampleInterval(thirty, .nan) == thirty)
    }

    @Test func densifyNeverExceedsThirtyFps() {
        // Dense glTF keys (corpus ~87/50/54 fps) must floor at defaultInterval.
        let denserThanThirty: Float = 1 / 87
        let interval = AnimationSampling.sampleInterval(
            averageKeyDuration: denserThanThirty,
            maximum: AnimationSampling.defaultInterval
        )
        #expect(interval == AnimationSampling.defaultInterval)
        let merged = AnimationSampling.mergeSampleInterval(
            AnimationSampling.defaultInterval,
            denserThanThirty
        )
        #expect(merged == AnimationSampling.defaultInterval)
    }

    @Test func sampleTimesNeverUsesZeroStride() {
        #expect(AnimationSampling.sampleTimes(from: 0, through: 0, by: 0) == [0])
        #expect(!AnimationSampling.sampleTimes(from: 0, through: 1, by: .nan).isEmpty)
    }

    @MainActor
    @Test func loadsClipWithZeroDurationSiblingChannel() async throws {
        let model = try await loadModel(try zeroDurationSiblingChannelGLB(), includeAnimations: true)
        #expect(firstComponent(ModelComponent.self, in: model.entity) != nil)
    }

    @Test func cubicLookupDoesNotTrapOnShortOutput() {
        let cubic = AnimatedVector3(
            keyTimes: [0, 1],
            values: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)],
            interpolation: .cubic
        )
        _ = cubic.value(at: 0.5)
        #expect(cubic.value(at: 0).x == 0)
    }

    @Test func linearLookupDoesNotTrapOnMismatchedCounts() {
        let sparse = AnimatedVector3(
            keyTimes: [0, 0.5, 1],
            values: [SIMD3(2, 0, 0)],
            interpolation: .linear
        )
        #expect(sparse.value(at: 1) == SIMD3(2, 0, 0))
    }

    @MainActor
    @Test func loadsClipWhenAccessorOmitsMinMax() async throws {
        let model = try await loadModel(try translationClipWithoutMinMaxGLB(), includeAnimations: true)
        #expect(!model.entity.availableAnimations.isEmpty)
    }

    @MainActor
    @Test func loadsUndersizedCubicSplineClip() async throws {
        let model = try await loadModel(try undersizedCubicSplineGLB(), includeAnimations: true)
        #expect(firstComponent(ModelComponent.self, in: model.entity) != nil)
    }
}

/// One moving node plus a 1-keyframe sibling. The clip stays (duration > 0) but
/// the sibling used to call `stride(..., by: 0)` and trap.
private func zeroDurationSiblingChannelGLB() throws -> Data {
    var bin = Data()
    appendFloats(floatTrianglePositions(), to: &bin)
    let positionsLength = bin.count
    appendFloats([0, 1], to: &bin)
    let movingTimesOffset = positionsLength
    let movingTimesLength = bin.count - movingTimesOffset
    appendFloats([0, 0, 0, 1, 0, 0], to: &bin)
    let movingValuesOffset = movingTimesOffset + movingTimesLength
    let movingValuesLength = bin.count - movingValuesOffset
    appendFloats([0], to: &bin)
    let stillTimesOffset = movingValuesOffset + movingValuesLength
    let stillTimesLength = bin.count - stillTimesOffset
    appendFloats([0, 0, 0], to: &bin)
    let stillValuesOffset = stillTimesOffset + stillTimesLength
    let stillValuesLength = bin.count - stillValuesOffset

    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionsLength],
            ["buffer": 0, "byteOffset": movingTimesOffset, "byteLength": movingTimesLength],
            ["buffer": 0, "byteOffset": movingValuesOffset, "byteLength": movingValuesLength],
            ["buffer": 0, "byteOffset": stillTimesOffset, "byteLength": stillTimesLength],
            ["buffer": 0, "byteOffset": stillValuesOffset, "byteLength": stillValuesLength],
        ],
        "accessors": [
            [
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [0, 0, 0],
                "max": [1, 1, 0],
            ],
            [
                "bufferView": 1,
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
                "min": [0],
                "max": [1],
            ],
            [
                "bufferView": 2,
                "componentType": 5126,
                "count": 2,
                "type": "VEC3",
            ],
            [
                "bufferView": 3,
                "componentType": 5126,
                "count": 1,
                "type": "SCALAR",
                "min": [0],
                "max": [0],
            ],
            [
                "bufferView": 4,
                "componentType": 5126,
                "count": 1,
                "type": "VEC3",
            ],
        ],
        "meshes": [["primitives": [["attributes": ["POSITION": 0], "mode": 4]]]],
        "nodes": [
            ["name": "Moving", "mesh": 0],
            ["name": "Still"],
        ],
        "animations": [[
            "name": "mixed",
            "samplers": [
                ["input": 1, "output": 2, "interpolation": "LINEAR"],
                ["input": 3, "output": 4, "interpolation": "LINEAR"],
            ],
            "channels": [
                ["sampler": 0, "target": ["node": 0, "path": "translation"]],
                ["sampler": 1, "target": ["node": 1, "path": "translation"]],
            ],
        ]],
        "scenes": [["nodes": [0, 1]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}

private func translationClipWithoutMinMaxGLB() throws -> Data {
    try translationClipGLB(
        times: [0, 1],
        values: [0, 0, 0, 1, 0, 0],
        interpolation: "LINEAR",
        includeTimeBounds: false
    )
}

private func undersizedCubicSplineGLB() throws -> Data {
    try translationClipGLB(
        times: [0, 1],
        values: [0, 0, 0, 1, 0, 0],
        interpolation: "CUBICSPLINE",
        includeTimeBounds: true
    )
}

private func translationClipGLB(
    times: [Float],
    values: [Float],
    interpolation: String,
    includeTimeBounds: Bool
) throws -> Data {
    var bin = Data()
    appendFloats(floatTrianglePositions(), to: &bin)
    let positionsLength = bin.count
    appendFloats(times, to: &bin)
    let timesOffset = positionsLength
    let timesLength = bin.count - timesOffset
    appendFloats(values, to: &bin)
    let valuesOffset = timesOffset + timesLength
    let valuesLength = bin.count - valuesOffset

    var timeAccessor: [String: Any] = [
        "bufferView": 1,
        "componentType": 5126,
        "count": times.count,
        "type": "SCALAR",
    ]
    if includeTimeBounds, let first = times.first, let last = times.last {
        timeAccessor["min"] = [first]
        timeAccessor["max"] = [last]
    }

    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionsLength],
            ["buffer": 0, "byteOffset": timesOffset, "byteLength": timesLength],
            ["buffer": 0, "byteOffset": valuesOffset, "byteLength": valuesLength],
        ],
        "accessors": [
            [
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [0, 0, 0],
                "max": [1, 1, 0],
            ],
            timeAccessor,
            [
                "bufferView": 2,
                "componentType": 5126,
                "count": values.count / 3,
                "type": "VEC3",
            ],
        ],
        "meshes": [["primitives": [["attributes": ["POSITION": 0], "mode": 4]]]],
        "nodes": [["mesh": 0]],
        "animations": [[
            "samplers": [["input": 1, "output": 2, "interpolation": interpolation]],
            "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
        ]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}
