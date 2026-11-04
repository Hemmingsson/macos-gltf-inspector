import CoreGraphics
import Foundation
import GLTFKit2
import Metal
import simd
import Testing
@testable import Renderer

/// Per-frame node worlds from `AnimationPose`. Expectations are the glTF lerp and gl-matrix
/// `fromRotationTranslationScale`, not values read back from `drawTransforms`.
@MainActor
@Suite(.serialized)
struct MetalPoseTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    private func loadClips(_ url: URL) throws -> [AnimationClip] {
        GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"
        let options: [GLTFAssetLoadingOption: Any] = [.assetDirectoryURLKey: url.deletingLastPathComponent()]
        return try AnimationClipLoader.loadClips(from: GLTFAsset(url: url, options: options))
    }

    private func pose(at time: Float, url: URL) throws -> AnimationPose {
        AnimationPose(
            clips: try loadClips(url),
            at: time,
            matrixAuthoredNodes: AnimationClipLoader.matrixAuthoredNodeIndices(sourceURL: url)
        )
    }

    /// gl-matrix `fromRotationTranslationScale` (column-major Float32). T · R · S.
    private func khronosTRS(translation t: SIMD3<Float>, rotation q: simd_quatf, scale s: SIMD3<Float>) -> simd_float4x4 {
        let x = q.vector.x, y = q.vector.y, z = q.vector.z, w = q.vector.w
        let x2 = x + x, y2 = y + y, z2 = z + z
        let xx = x * x2, xy = x * y2, xz = x * z2
        let yy = y * y2, yz = y * z2, zz = z * z2
        let wx = w * x2, wy = w * y2, wz = w * z2
        return simd_float4x4(columns: (
            SIMD4((1 - (yy + zz)) * s.x, (xy + wz) * s.x, (xz - wy) * s.x, 0),
            SIMD4((xy - wz) * s.y, (1 - (xx + zz)) * s.y, (yz + wx) * s.y, 0),
            SIMD4((xz + wy) * s.z, (yz - wx) * s.z, (1 - (xx + yy)) * s.z, 0),
            SIMD4(t.x, t.y, t.z, 1)
        ))
    }

    /// BoxAnimated translation keys: t = 0 → y 0, t = 1.25 → y 2.52. Linear at 0.5 s.
    private var boxAnimatedHeight: Float {
        let y0: Float = 0
        let y1: Float = 2.5199999809265137
        let tn = (Float(0.5) - 0) / (Float(1.25) - 0)
        return y0 + tn * (y1 - y0)
    }

    /// Rx(−90°): world +Y lands on view −Z, so a Y translation changes sort depth.
    private var tiltYIntoViewZ: simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 0, -1, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    /// Camera at z = 5 looking down −Z. View-space Z is world Z minus 5.
    private var cameraAtZ5: simd_float4x4 {
        var view = matrix_identity_float4x4
        view.columns.3 = SIMD4(0, 0, -5, 1)
        return view
    }

    @Test func boxAnimatedPoseReachesEncodingAndChangesSortDepth() async throws {
        let scene = try await MetalSceneLoader.load(url: TestFixtures.boxAnimated, device: device())
        let animation = try pose(at: 0.5, url: TestFixtures.boxAnimated)
        let y = boxAnimatedHeight
        let expected = khronosTRS(
            translation: SIMD3(0, y, 0),
            rotation: simd_quatf(vector: SIMD4(0, 0, 0, -1)),
            scale: SIMD3(repeating: 1)
        )
        let transforms = scene.drawTransforms(pose: animation)
        let inner = try #require(scene.draws.firstIndex { $0.nodeIndex == 2 })
        let outer = try #require(scene.draws.firstIndex { $0.nodeIndex == 3 })

        #expect(transforms[inner].model == expected)
        #expect(transforms[inner].normalMatrix == expected.inverse.transpose)
        #expect(transforms[inner].negativeScale == false)
        #expect(transforms[outer].model == scene.draws[outer].worldTransform)

        let restDepth = MetalDrawLists.viewDepth(centroid: scene.draws[inner].centroid, model: scene.draws[inner].worldTransform, view: tiltYIntoViewZ)
        let posedDepth = MetalDrawLists.viewDepth(centroid: scene.draws[inner].centroid, model: transforms[inner].model, view: tiltYIntoViewZ)
        #expect(posedDepth != restDepth)
        #expect(posedDepth < restDepth, "the box moves toward +Y, which this tilt maps to a farther view Z")

        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.boxAnimated)
        let encoded = renderer.frameDraws(options: ViewOptions(), animationPose: animation, view: tiltYIntoViewZ)
        #expect(encoded.transforms[inner].model == expected)
        #expect(encoded.transforms[inner].normalMatrix == expected.inverse.transpose)

        let camera = MetalCameraPose(azimuth: 25, elevation: -18, distance: 6, target: .zero,
                                     yfov: .pi / 4, znear: 0.05, zfar: 50)
        let restImage = try renderer.image(ViewOptions(), pose: camera, width: 48, height: 48)
        let posedImage = try renderer.image(ViewOptions(), pose: camera, width: 48, height: 48, animationPose: animation)
        #expect(pixelBytes(restImage) != pixelBytes(posedImage))

        let blendURL = try blendPairGLB()
        defer { try? FileManager.default.removeItem(at: blendURL) }
        let blend = try await MetalSceneLoader.load(url: blendURL, device: device())
        var lists = MetalDrawLists(draws: blend.draws)
        let restOrder = lists.frame(draws: blend.draws, view: cameraAtZ5).main
        #expect(restOrder == [1, 0])
        var moved = blend.draws.map(\.worldTransform)
        moved[0].columns.3.z = -4
        #expect(lists.frame(draws: blend.draws, models: moved, view: cameraAtZ5).main == [0, 1])
        let blendPose = try pose(at: 1, url: blendURL)
        let posedModels = blend.drawTransforms(pose: blendPose).map(\.model)
        #expect(lists.frame(draws: blend.draws, models: posedModels, view: cameraAtZ5).main == [0, 1])
    }

    @Test func negativeScaleFlipsFrontFaceAndPosesChildren() async throws {
        let url = try negativeScaleGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        let animation = try pose(at: 1, url: url)
        let transforms = scene.drawTransforms(pose: animation)
        let parent = try #require(scene.draws.firstIndex { $0.nodeIndex == 0 })
        let child = try #require(scene.draws.firstIndex { $0.nodeIndex == 1 })

        let parentLocal = khronosTRS(translation: .zero, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: SIMD3(-1, 1, 1))
        let childLocal = khronosTRS(translation: SIMD3(2, 0, 0), rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: SIMD3(repeating: 1))
        let childWorld = parentLocal * childLocal
        #expect(transforms[parent].model == parentLocal)
        #expect(transforms[parent].negativeScale == true)
        #expect(transforms[parent].normalMatrix == parentLocal.inverse.transpose)
        #expect(transforms[child].model == childWorld)
        #expect(transforms[child].model.columns.3.x == -2)
        #expect(transforms[child].negativeScale == true)
        #expect(simd_determinant(transforms[child].model) < 0)

        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let encoded = renderer.frameDraws(options: ViewOptions(), animationPose: animation, view: matrix_identity_float4x4)
        #expect(encoded.transforms[parent].negativeScale == true)
        #expect(encoded.transforms[child].model.columns.3.x == -2)
    }

    @Test func restPoseKeepsCachedWorldsAndFilters() async throws {
        let url = try negativeScaleGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        let rest = scene.drawTransforms(pose: nil)
        let empty = scene.drawTransforms(pose: AnimationPose())
        #expect(rest == empty)
        for (draw, transform) in zip(scene.draws, rest) {
            #expect(transform.model == draw.worldTransform)
            #expect(transform.normalMatrix == draw.worldTransform.inverse.transpose)
            #expect(transform.negativeScale == draw.negativeScale)
        }

        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        func drawn(_ options: ViewOptions) -> [Int] {
            renderer.frameDraws(options: options, animationPose: nil, view: matrix_identity_float4x4)
                .main.map { scene.draws[$0].nodeIndex }
        }
        #expect(drawn(ViewOptions()) == [0, 1])
        #expect(drawn(ViewOptions(hiddenNodeIndices: [1])) == [0])
        #expect(drawn(ViewOptions(hiddenNodeIndices: [0])) == [])
        #expect(drawn(ViewOptions(soloNodeIndices: [1])) == [1])
        #expect(drawn(ViewOptions(isolatedNodeIndex: 0)) == [0])
        #expect(drawn(ViewOptions(isolatedNodeIndex: 1)) == [1])

        let encoded = renderer.frameDraws(options: ViewOptions(hiddenNodeIndices: [1]), animationPose: nil, view: matrix_identity_float4x4)
        #expect(encoded.transforms[0].model == scene.draws[0].worldTransform)
    }

    private func pixelBytes(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data else { return [] }
        return [UInt8](data as Data)
    }

    /// Two blend triangles. Node 0 sits at z = 0 and animates to z = −4; node 1 stays at z = −2.
    private func blendPairGLB() throws -> URL {
        try animatedTriangleGLB(
            nodes: [
                ["mesh": 0, "translation": [0, 0, 0]],
                ["mesh": 0, "translation": [0, 0, -2]],
            ],
            path: "translation",
            node: 0,
            times: [0, 1],
            values: [0, 0, 0, 0, 0, -4],
            alphaMode: "BLEND",
            roots: [0, 1]
        )
    }

    /// Parent scale animates to (−1, 1, 1). Child is translated +2 on X, so its world X becomes −2.
    private func negativeScaleGLB() throws -> URL {
        try animatedTriangleGLB(
            nodes: [
                ["mesh": 0, "children": [1]],
                ["mesh": 0, "translation": [2, 0, 0]],
            ],
            path: "scale",
            node: 0,
            times: [0, 1],
            values: [1, 1, 1, -1, 1, 1]
        )
    }

    private func animatedTriangleGLB(
        nodes: [[String: Any]],
        path: String,
        node: Int,
        times: [Float],
        values: [Float],
        alphaMode: String? = nil,
        roots: [Int] = [0]
    ) throws -> URL {
        var bin = floatTriangleBin()
        let timeOffset = bin.count
        appendFloats(times, to: &bin)
        let valueOffset = bin.count
        appendFloats(values, to: &bin)
        var material: [String: Any] = [:]
        if let alphaMode { material["alphaMode"] = alphaMode }
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": bin.count]],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": timeOffset],
                ["buffer": 0, "byteOffset": timeOffset, "byteLength": valueOffset - timeOffset],
                ["buffer": 0, "byteOffset": valueOffset, "byteLength": bin.count - valueOffset],
            ],
            "accessors": [
                ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]],
                ["bufferView": 1, "componentType": 5126, "count": times.count, "type": "SCALAR", "min": [times.min() ?? 0], "max": [times.max() ?? 0]],
                ["bufferView": 2, "componentType": 5126, "count": values.count / 3, "type": "VEC3"],
            ],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
            "materials": [material],
            "nodes": nodes,
            "scenes": [["nodes": roots]],
            "scene": 0,
            "animations": [[
                "samplers": [["input": 1, "output": 2, "interpolation": "LINEAR"]],
                "channels": [["sampler": 0, "target": ["node": node, "path": path]]],
            ]],
        ]
        return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "metal-pose")
    }
}
