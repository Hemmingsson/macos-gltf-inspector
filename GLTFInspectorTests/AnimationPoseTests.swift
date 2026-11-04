import Foundation
import GLTFKit2
import simd
import Testing
@testable import Renderer

struct AnimationPoseTests {
    private func loadAsset(_ url: URL) throws -> GLTFAsset {
        GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"
        let options: [GLTFAssetLoadingOption: Any] = [.assetDirectoryURLKey: url.deletingLastPathComponent()]
        return try GLTFAsset(url: url, options: options)
    }

    private func loadClips(_ url: URL) throws -> [AnimationClip] {
        try AnimationClipLoader.loadClips(from: loadAsset(url))
    }

    private static let interpolationTest = TestFixtures.url(
        "TestModels/Khronos samples/InterpolationTest/InterpolationTest.glb"
    )

    @Test func handAuthoredTRSAtHalfSecond() {
        let clipMax: Float = 1
        let translation = AnimationClipChannel(
            target: .translation(nodeIndex: 0),
            sampler: AnimationSampler(
                input: [0, 1],
                output: [0, 0, 0, 0, 2, 0],
                componentCount: 3,
                interpolation: .linear,
                clipMaxTime: clipMax
            )
        )
        let rotation = AnimationClipChannel(
            target: .rotation(nodeIndex: 0),
            sampler: AnimationSampler(
                input: [0, 1],
                output: [0, 0, 0, 1, 0, 0.70710677, 0, 0.70710677],
                componentCount: 4,
                interpolation: .linear,
                clipMaxTime: clipMax,
                isRotation: true
            )
        )
        let clip = AnimationClip(name: "hand", channels: [translation, rotation])
        let pose = AnimationPose(clips: [clip], at: 0.5)

        let override = pose.nodeOverrides[0]
        #expect(override != nil)
        if let t = override?.translation {
            #expect(abs(t.y - 1) < 1e-5)
            #expect(abs(t.x) < 1e-5 && abs(t.z) < 1e-5)
        }
        if let q = override?.rotation {
            // Halfway slerp from identity to 90° about Y → 45° about Y.
            #expect(abs(q.vector.y - 0.38268343) < 1e-4)
            #expect(abs(q.vector.w - 0.9238795) < 1e-4)
        } else {
            Issue.record("Expected rotation override")
        }
    }

    @Test func boxAnimatedPoseAtHalfSecond() throws {
        let clips = try loadClips(TestFixtures.boxAnimated)
        let pose = AnimationPose(clips: clips, at: 0.5)

        let root = pose.nodeOverrides[0]
        #expect(root?.translation != nil)
        if let t = root?.translation {
            #expect(abs(t.y - 1.0079999923706056) < 1e-5)
            #expect(abs(t.x) < 1e-5 && abs(t.z) < 1e-5)
        }

        let rot = pose.nodeOverrides[2]?.rotation
        #expect(rot != nil)
        if let rot {
            #expect(abs(rot.vector.w + 1) < 1e-4)
            #expect(abs(rot.vector.x) + abs(rot.vector.y) + abs(rot.vector.z) < 1e-4)
        }
    }

    @Test func interpolationTestLinearTranslationAtHalfSecond() throws {
        let clips = try loadClips(Self.interpolationTest)
        let clip = clips[8]
        #expect(clip.name == "Linear Translation")
        let pose = AnimationPose(clips: [clip], at: 0.5)
        let t = pose.nodeOverrides[8]?.translation
        #expect(t != nil)
        if let t {
            #expect(abs(t.x + 3.4) < 1e-4)
            #expect(abs(t.y - 10.8) < 1e-4)
            #expect(abs(t.z) < 1e-5)
        }
    }

    @Test func untargetedNodesKeepRestOverridesAbsent() throws {
        let clips = try loadClips(TestFixtures.boxAnimated)
        let pose = AnimationPose(clips: clips, at: 0.5)
        #expect(pose.nodeOverrides[1] == nil)
    }

    @Test func matrixAuthoredNodeIgnoresTRSChannels() throws {
        let times: [Float] = [0, 1]
        let translations: [Float] = [0, 0, 0, 5, 0, 0]
        var bin = Data()
        appendFloats(times, to: &bin)
        appendFloats(translations, to: &bin)
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": bin.count]],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": 8],
                ["buffer": 0, "byteOffset": 8, "byteLength": 24],
            ],
            "accessors": [
                ["bufferView": 0, "componentType": 5126, "count": 2, "type": "SCALAR"],
                ["bufferView": 1, "componentType": 5126, "count": 2, "type": "VEC3"],
            ],
            "animations": [[
                "samplers": [["input": 0, "output": 1, "interpolation": "LINEAR"]],
                "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
            ]],
            "nodes": [
                ["matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]],
                ["translation": [0, 0, 0]],
            ],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ]
        let url = try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "matrix-node")
        defer { try? FileManager.default.removeItem(at: url) }

        let clips = try loadClips(url)
        let matrixNodes = AnimationClipLoader.matrixAuthoredNodeIndices(sourceURL: url)
        #expect(matrixNodes.contains(0))
        let pose = AnimationPose(clips: clips, at: 0.5, matrixAuthoredNodes: matrixNodes)
        #expect(pose.nodeOverrides[0] == nil)
        #expect(pose.nodeOverrides[1] == nil)
    }

    @Test func nodeMorphWeightsLandInNodeWeightsMap() {
        let clip = AnimationClip(name: "weights", channels: [
            AnimationClipChannel(
                target: .weightsOnNode(nodeIndex: 0),
                sampler: AnimationSampler(
                    input: [0, 1],
                    output: [0, 1, 1, 0],
                    componentCount: 2,
                    interpolation: .linear,
                    clipMaxTime: 1
                )
            ),
        ])
        let pose = AnimationPose(clips: [clip], at: 0.5)
        #expect(pose.meshWeights.isEmpty)
        let w = pose.nodeWeights[0]
        #expect(w?.count == 2)
        if let w {
            #expect(abs(w[0] - 0.5) < 1e-5)
            #expect(abs(w[1] - 0.5) < 1e-5)
        }
    }

    @Test func meshWeightsLandInMeshWeightsMap() {
        let clip = AnimationClip(name: "meshWeights", channels: [
            AnimationClipChannel(
                target: .weightsOnMesh(meshIndex: 0),
                sampler: AnimationSampler(
                    input: [0, 1],
                    output: [0, 1, 1, 0],
                    componentCount: 2,
                    interpolation: .linear,
                    clipMaxTime: 1
                )
            ),
        ])
        let pose = AnimationPose(clips: [clip], at: 0.5)
        #expect(pose.nodeWeights.isEmpty)
        #expect(abs((pose.meshWeights[0]?[0] ?? -1) - 0.5) < 1e-5)
    }

    @Test func defaultSelectionIsDisjointInStableOrder() throws {
        let clips = try loadClips(Self.interpolationTest)
        let selected = AnimationClip.defaultSelectedClipIndices(in: clips)
        #expect(selected == Array(0 ..< clips.count))

        let a = AnimationClip(name: "a", channels: [
            AnimationClipChannel(
                target: .translation(nodeIndex: 0),
                sampler: AnimationSampler(input: [0], output: [0, 0, 0], componentCount: 3, interpolation: .linear, clipMaxTime: 1)
            ),
        ])
        let b = AnimationClip(name: "b", channels: [
            AnimationClipChannel(
                target: .translation(nodeIndex: 0),
                sampler: AnimationSampler(input: [0], output: [1, 0, 0], componentCount: 3, interpolation: .linear, clipMaxTime: 1)
            ),
        ])
        let c = AnimationClip(name: "c", channels: [
            AnimationClipChannel(
                target: .rotation(nodeIndex: 0),
                sampler: AnimationSampler(input: [0], output: [0, 0, 0, 1], componentCount: 4, interpolation: .linear, clipMaxTime: 1, isRotation: true)
            ),
        ])
        #expect(AnimationClip.defaultSelectedClipIndices(in: [a, b, c]) == [0, 2])
    }

    @Test func clipMaxTimeIsMaximumInputEnd() throws {
        let clips = try loadClips(TestFixtures.boxAnimated)
        #expect(abs(clips[0].maxTime - 3.708329916000366) < 1e-4)

        let short = AnimationClip(name: "short", channels: [
            AnimationClipChannel(
                target: .translation(nodeIndex: 0),
                sampler: AnimationSampler(input: [0, 2], output: [0, 0, 0, 1, 0, 0], componentCount: 3, interpolation: .linear, clipMaxTime: 10)
            ),
        ])
        #expect(abs(short.maxTime - 2) < 1e-6)
        let pose = AnimationPose(clips: [short], at: 7)
        #expect(abs((pose.nodeOverrides[0]?.translation?.x ?? 0) - 1) < 1e-5)
    }
}
