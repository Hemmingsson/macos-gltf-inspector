import Foundation
import Metal
import simd
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct MetalPickTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    private func frontPose() -> MetalCameraPose {
        MetalCameraPose(azimuth: 0, elevation: 0, distance: 5, target: SIMD3(0, 0, 0),
                        yfov: .pi / 3, znear: 0.1, zfar: 100)
    }

    private func center(of size: Int) -> SIMD2<Int> { SIMD2(size / 2, size / 2) }

    @Test func stackedQuadsPickFrontThenBackWhenHidden() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        let point = center(of: size)
        #expect(try renderer.pick(ViewOptions(), pose: frontPose(), width: size, height: size, point: point) == 1)
        let hidden = ViewOptions(hiddenNodeIndices: [1])
        #expect(try renderer.pick(hidden, pose: frontPose(), width: size, height: size, point: point) == 0)
    }

    @Test func backgroundPixelReturnsNil() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        #expect(try renderer.pick(ViewOptions(), pose: frontPose(), width: size, height: size, point: SIMD2(0, 0)) == nil)
    }

    @Test func maskHoleClicksThroughToMeshBehind() async throws {
        let url = try writeTempMaskOverOpaqueGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        let center = center(of: size)
        #expect(try renderer.pick(ViewOptions(), pose: frontPose(), width: size, height: size, point: center) == 0)
        let onlyFront = ViewOptions(hiddenNodeIndices: [0])
        #expect(try renderer.pick(onlyFront, pose: frontPose(), width: size, height: size, point: center) == nil)
    }

    @Test func transparentPickingUsesNearestSurfaceRatherThanCentroidOrder() async throws {
        let positions: [Float] = [
            -1, -1, 2, 1, -1, 2, 1, 1, 2, -1, -1, 2, 1, 1, 2, -1, 1, 2,
            20, -1, -100, 22, -1, -100, 22, 1, -100, 20, -1, -100, 22, 1, -100, 20, 1, -100,
            -1, -1, 1, 1, -1, 1, 1, 1, 1, -1, -1, 1, 1, 1, 1, -1, 1, 1,
        ]
        var bin = Data()
        appendFloats(positions, to: &bin)
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": bin.count]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 144],
                            ["buffer": 0, "byteOffset": 144, "byteLength": 72]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 12, "type": "VEC3",
                           "min": [-1, -1, -100], "max": [22, 1, 2]],
                          ["bufferView": 1, "componentType": 5126, "count": 6, "type": "VEC3",
                           "min": [-1, -1, 1], "max": [1, 1, 1]]],
            "materials": [["alphaMode": "BLEND", "doubleSided": true,
                           "pbrMetallicRoughness": ["baseColorFactor": [1, 0, 0, 1]]]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]],
                       ["primitives": [["attributes": ["POSITION": 1], "material": 0]]]],
            "nodes": [["mesh": 0], ["mesh": 1]], "scenes": [["nodes": [0, 1]]], "scene": 0,
        ]
        let url = try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "review-blend-pick")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        #expect(try renderer.pick(ViewOptions(), pose: frontPose(), width: 64, height: 64,
                                  point: SIMD2(32, 32)) == 0,
                "node 0's surface is at z=2; node 1 is behind at z=1")
    }

    @Test func fullyTransparentBlendQuadInFrontPicksOpaqueMeshBehind() async throws {
        let url = try writeTempBlendFrontGLB(frontAlpha: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        #expect(try renderer.pick(ViewOptions(), pose: frontPose(), width: 64, height: 64,
                                  point: center(of: 64)) == 0)
    }

    @Test func opaqueEnoughBlendQuadInFrontPicksItself() async throws {
        let url = try writeTempBlendFrontGLB(frontAlpha: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        #expect(try renderer.pick(ViewOptions(), pose: frontPose(), width: 64, height: 64,
                                  point: center(of: 64)) == 1)
    }

    /// Opaque quad at z = -1 (node 0) behind a full-size BLEND quad at z = 1 (node 1) whose base alpha is `frontAlpha`.
    private func writeTempBlendFrontGLB(frontAlpha: Float) throws -> URL {
        let back: [Float] = [-1, -1, -1, 1, -1, -1, 1, 1, -1, -1, -1, -1, 1, 1, -1, -1, 1, -1]
        let front: [Float] = [-1, -1, 1, 1, -1, 1, 1, 1, 1, -1, -1, 1, 1, 1, 1, -1, 1, 1]
        var bin = Data()
        appendFloats(back, to: &bin)
        appendFloats(front, to: &bin)
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": bin.count]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 72],
                            ["buffer": 0, "byteOffset": 72, "byteLength": 72]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 6, "type": "VEC3",
                           "min": [-1, -1, -1], "max": [1, 1, -1]],
                          ["bufferView": 1, "componentType": 5126, "count": 6, "type": "VEC3",
                           "min": [-1, -1, 1], "max": [1, 1, 1]]],
            "materials": [["name": "Opaque", "doubleSided": true,
                           "pbrMetallicRoughness": ["baseColorFactor": [1, 1, 1, 1]]],
                          ["name": "Glass", "alphaMode": "BLEND", "doubleSided": true,
                           "pbrMetallicRoughness": ["baseColorFactor": [1, 0, 0, frontAlpha]]]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]],
                       ["primitives": [["attributes": ["POSITION": 1], "material": 1]]]],
            "nodes": [["mesh": 0], ["mesh": 1]], "scenes": [["nodes": [0, 1]]], "scene": 0,
        ]
        return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "blend-front")
    }

    @Test func fileCameraUsesAuthoredView() async throws {
        let url = try writeTempCameraPickGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        let point = center(of: size)
        #expect(try renderer.pick(ViewOptions(fileCameraNodeIndex: 1), pose: frontPose(),
                                  width: size, height: size, point: point) == 0)
    }

    @Test func nearerLightGizmoDepthIsLessThanFartherQuad() async throws {
        let light: [String: Any] = ["name": "Lamp", "translation": [0, 0, 2],
                                    "extensions": ["KHR_lights_punctual": ["light": 0]]]
        let url = try reviewQuadsGLB([(cx: 0, z: 0, h: 2)], extraNodes: [light],
                                     extensions: ["KHR_lights_punctual": ["lights": [["type": "point"]]]],
                                     prefix: "review2-r9-depth")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let scene = try #require(renderer.scene)
        let options = ViewOptions(showsSceneGizmos: true)
        let pose = frontPose()
        let size = 64
        let point = center(of: size)
        let mesh = try renderer.pickResult(options, pose: pose, width: size, height: size, point: point)
        #expect(mesh.nodeIndex == 0)
        let frame = try renderer.gizmoPickFrame(options: options, pose: pose, width: size, height: size)
        let segments = overlayGizmoSegments(scene: scene, options: MetalOverlayOptions(sceneGizmos: true))
        let gizmo = gizmoHitResult(at: SIMD2(Float(point.x), Float(point.y)), segments: segments,
                                   viewProjection: frame.viewProjection,
                                   viewport: GizmoHitViewport(viewWidthPoints: Float(size), viewHeightPoints: Float(size),
                                                              contentAspect: frame.viewportAspect))
        let gizmoHit = try #require(gizmo)
        #expect(gizmoHit.nodeIndex == 1)
        #expect(gizmoHit.depth <= mesh.depth + 1e-4)
    }

    @Test func gizmoPickFrameUsesTheSameCameraAsPickPass() async throws {
        let url = try writeTempCameraPickGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let scene = try #require(renderer.scene)
        let options = ViewOptions(fileCameraNodeIndex: 1, showsSceneGizmos: true)
        let size = 64
        let frame = try renderer.gizmoPickFrame(options: options, pose: frontPose(), width: size, height: size)
        let fileCamera = try #require(scene.fileCamera(at: 1, aspect: Float(size) / Float(size)))
        #expect(frame.viewProjection == fileCamera.viewProjection)
    }
}
