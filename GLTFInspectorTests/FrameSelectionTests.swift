import Foundation
import Metal
import simd
import Testing
@testable import GLTFInspector
@testable import Renderer

@MainActor
@Suite(.serialized)
struct FrameSelectionTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    private func settings() throws -> AppSettings {
        let suite = "gltf.frame-selection.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    /// Two meshes: a unit triangle at the origin and a triangle translated to (10, 0, 0).
    private func offsetChildGLB() throws -> URL {
        var bin = Data()
        appendFloats(floatTrianglePositions(), to: &bin)
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": bin.count]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
            "accessors": [[
                "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
                "min": [0, 0, 0], "max": [1, 1, 0],
            ]],
            "meshes": [
                ["primitives": [["attributes": ["POSITION": 0]]]],
                ["primitives": [["attributes": ["POSITION": 0]]]],
            ],
            "nodes": [
                ["name": "Root", "children": [1, 2]],
                ["name": "Near", "mesh": 0],
                ["name": "Far", "mesh": 1, "translation": [10, 0, 0]],
            ],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ]
        return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "frame-selection")
    }

    @Test func frameNodeMovesTargetToSubtreeCentreAndKeepsOrbit() async throws {
        let url = try offsetChildGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        view.frame = NSRect(x: 0, y: 0, width: 512, height: 512)
        try await view.load(url)
        view.fit()
        view.orbit(azimuth: 40, elevation: -15)
        let azimuth = view.camera.rotAroundY
        let elevation = view.camera.rotAroundX

        view.frame(nodeIndex: 2)

        #expect(abs(view.camera.rotAroundY - azimuth) < 1e-12)
        #expect(abs(view.camera.rotAroundX - elevation) < 1e-12)
        let target = view.camera.target
        // Far triangle spans [10,11]×[0,1]×0 → centre (10.5, 0.5, 0)
        #expect(abs(target.x - 10.5) < 0.05)
        #expect(abs(target.y - 0.5) < 0.05)
        #expect(abs(target.z) < 0.05)
    }

    @Test func frameSelectionNoopsWithoutSceneNodeAndClearsFileCamera() throws {
        let view = ViewState(settings: try settings())
        view.fileCameraNodeIndex = 3
        view.selection = NodeID(kind: .material, index: 0)
        view.frameSelection()
        #expect(view.fileCameraNodeIndex == 3, "non-node selection must not clear the file camera")

        view.selection = NodeID(kind: .mesh, index: 1)
        view.show(.front)
        #expect(view.activeCameraPreset == .front)
        // No loaded canvas scene: frame still clears framing state.
        view.frameSelection()
        #expect(view.fileCameraNodeIndex == nil)
        #expect(view.activeCameraPreset == nil)
    }

    /// Two-sided quads (two triangles each) at the given z, spanning ±h in x/y around cx.
    private func quads(_ specs: [(cx: Float, z: Float, h: Float)]) throws -> URL {
        var bin = Data()
        var bufferViews: [[String: Any]] = [], accessors: [[String: Any]] = [], meshes: [[String: Any]] = []
        var nodes: [[String: Any]] = []
        for (i, q) in specs.enumerated() {
            let a: [Float] = [q.cx - q.h, -q.h, q.z, q.cx + q.h, -q.h, q.z, q.cx + q.h, q.h, q.z,
                              q.cx - q.h, -q.h, q.z, q.cx + q.h, q.h, q.z, q.cx - q.h, q.h, q.z]
            let offset = bin.count
            appendFloats(a, to: &bin)
            bufferViews.append(["buffer": 0, "byteOffset": offset, "byteLength": 72])
            accessors.append(["bufferView": i, "componentType": 5126, "count": 6, "type": "VEC3",
                              "min": [q.cx - q.h, -q.h, q.z], "max": [q.cx + q.h, q.h, q.z]])
            meshes.append(["primitives": [["attributes": ["POSITION": i], "material": 0]]])
            nodes.append(["mesh": i])
        }
        let json: [String: Any] = [
            "asset": ["version": "2.0"], "buffers": [["byteLength": bin.count]],
            "bufferViews": bufferViews, "accessors": accessors,
            "materials": [["doubleSided": true]], "meshes": meshes, "nodes": nodes,
            "scenes": [["nodes": Array(0..<nodes.count)]], "scene": 0,
        ]
        return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "frame-selection-quads")
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    @Test func frameSelectionKeepsTheRestOfTheSceneInsideTheClipRange() async throws {
        // Small quad at the origin; big quad 20 units behind it (further from the front camera).
        let url = try quads([(cx: 0, z: 0, h: 0.05), (cx: 0, z: -20, h: 5)])
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(url)
        let sceneMin = view.camera.sceneMin, sceneMax = view.camera.sceneMax
        view.frame(nodeIndex: 0)
        let eye = view.camera.position
        let depth = simd_dot(SIMD3<Double>(0, 0, -20) - eye, view.camera.lookDirection)
        #expect(view.camera.zfar > depth, "zfar \(view.camera.zfar) clips the background quad at depth \(depth)")
        #expect(view.camera.sceneMin == sceneMin && view.camera.sceneMax == sceneMax,
                "floor/gizmo extents changed from \(sceneMin)…\(sceneMax) to \(view.camera.sceneMin)…\(view.camera.sceneMax)")
    }

    @Test func frameSelectionStillDrawsTheFarMesh() async throws {
        let withFar = try quads([(cx: 0, z: 0, h: 0.05), (cx: 0, z: -20, h: 20)])
        let alone = try quads([(cx: 0, z: 0, h: 0.05)])
        defer {
            try? FileManager.default.removeItem(at: withFar)
            try? FileManager.default.removeItem(at: alone)
        }
        let framedWithFar = ModelView(renderer: try MetalRenderer())
        try await framedWithFar.load(withFar)
        framedWithFar.frame(nodeIndex: 0)
        let framedAlone = ModelView(renderer: try MetalRenderer())
        try await framedAlone.load(alone)
        framedAlone.frame(nodeIndex: 0)
        // The near quad is identical in both renders, so any difference is the far quad.
        let far = pixels(try framedWithFar.image(width: 96, height: 96))
        let near = pixels(try framedAlone.image(width: 96, height: 96))
        let changed = zip(far, near).filter { abs(Int($0) - Int($1)) > 8 }.count
        #expect(changed > 0, "the far quad must still be drawn after framing")
    }

    /// Selecting a point-sized or zero-area node and framing it must leave a finite, valid
    /// projection and a renderable frame (s1pmqv4t).
    private func assertFiniteFrame(_ url: URL, node: Int, _ label: String) async throws {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(url)
        view.frame(nodeIndex: node)
        let camera = view.camera
        #expect(camera.zfar > camera.znear && camera.znear > 0, "\(label): znear \(camera.znear) zfar \(camera.zfar)")
        let projection = MetalCamera(pose: camera.pose, isOrthographic: false, aspect: 1).openGLProjectionMatrix
        #expect((0..<4).allSatisfy { column in (0..<4).allSatisfy { projection[column][$0].isFinite } },
                "\(label): non-finite projection")
        _ = try view.image(width: 64, height: 64)
    }

    @Test func frameCameraLeavesAFiniteProjection() async throws {
        try await assertFiniteFrame(TestFixtures.cameras, node: 1, "perspective camera")
        try await assertFiniteFrame(TestFixtures.cameras, node: 2, "orthographic camera")
    }

    @Test func frameLightLeavesAFiniteProjection() async throws {
        try await assertFiniteFrame(TestFixtures.lights, node: 1, "light")
    }

    @Test func frameJointLeavesAFiniteProjection() async throws {
        try await assertFiniteFrame(TestFixtures.rigged, node: 1, "joint")
        try await assertFiniteFrame(TestFixtures.rigged, node: 2, "leaf joint")
    }

    /// With Center Model off, selection framing must still target the selection's own centre,
    /// not a point between it and the origin (zeif47se).
    @Test func frameSelectionTargetsTheSelectionWhenCentringIsOff() async throws {
        let url = try quads([(cx: 10.5, z: 0, h: 0.5)])
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(url, options: ViewOptions(isCentered: false))
        view.orbit(azimuth: 40, elevation: -15)
        let azimuth = view.camera.rotAroundY, elevation = view.camera.rotAroundX

        view.frame(nodeIndex: 0)
        #expect(simd_distance(view.camera.target, SIMD3(10.5, 0, 0)) < 1e-3, "frame target \(view.camera.target)")
        #expect(abs(view.camera.rotAroundY - azimuth) < 1e-12 && abs(view.camera.rotAroundX - elevation) < 1e-12)

        view.fit(nodeIndex: 0)
        #expect(simd_distance(view.camera.target, SIMD3(10.5, 0, 0)) < 1e-3, "fit target \(view.camera.target)")
    }

    @Test func frameZeroAreaMeshLeavesAFiniteProjection() async throws {
        let url = try quads([(cx: 0, z: 0, h: 0)])
        defer { try? FileManager.default.removeItem(at: url) }
        try await assertFiniteFrame(url, node: 0, "zero-area mesh")
    }
}
