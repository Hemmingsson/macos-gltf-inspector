import Foundation
import Metal
import simd
import Testing
@testable import Renderer

/// The native port orders draws like the pinned Khronos `drawScene`: opaque instancing groups,
/// then transmission and transparent drawables sorted by view-space centroid depth.
struct MetalDrawOrderTests {
    /// Nodes in scene order (draw index = node index). The camera sits at z = 5 looking down -z.
    /// 0 blend z -1 · 1 opaque z 0 · 2 blend z -3 · 3 blend z +10 (behind the camera)
    /// 4 blend + transmission (factor 0) z 0 · 5 opaque + transmission z -2 · 6 opaque z 1
    /// 7 blend at the origin whose indexed centroid is z -10 (an unindexed vertex sits at z +100)
    /// 8 blend z -3, the same depth as 2
    private func fixture() throws -> URL {
        var bin = Data()
        func floats(_ values: [Float]) { values.forEach { withUnsafeBytes(of: $0.bitPattern.littleEndian) { bin.append(contentsOf: $0) } } }
        floats([-1, -1, 0, 1, -1, 0, 0, 1, 0])
        floats([-1, -1, -10, 1, -1, -10, 0, 1, -10, 0, 0, 100])
        [UInt16(0), 1, 2].forEach { withUnsafeBytes(of: $0.littleEndian) { bin.append(contentsOf: $0) } }
        let transmission = ["KHR_materials_transmission": ["transmissionFactor": 0.0]]
        func mesh(_ material: Int, position: Int = 0, indices: Int? = nil) -> [String: Any] {
            var primitive: [String: Any] = ["attributes": ["POSITION": position], "material": material]
            if let indices { primitive["indices"] = indices }
            return ["primitives": [primitive]]
        }
        func node(_ mesh: Int, _ z: Double) -> [String: Any] { ["mesh": mesh, "translation": [0, 0, z]] }
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "extensionsUsed": ["KHR_materials_transmission"],
            "scene": 0,
            "scenes": [["nodes": Array(0..<9)]],
            "nodes": [node(1, -1), node(0, 0), node(1, -3), node(1, 10), node(2, 0), node(3, -2),
                      node(0, 1), node(4, 0), node(1, -3)],
            "meshes": [mesh(0), mesh(1), mesh(2), mesh(3), mesh(1, position: 1, indices: 2)],
            "materials": [
                [:],
                ["alphaMode": "BLEND"],
                ["alphaMode": "BLEND", "extensions": transmission],
                ["extensions": ["KHR_materials_transmission": ["transmissionFactor": 1.0]]],
            ],
            "accessors": [
                ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]],
                ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC3", "min": [-1, -1, -10], "max": [1, 1, 100]],
                ["bufferView": 2, "componentType": 5123, "count": 3, "type": "SCALAR"],
            ],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": 36],
                ["buffer": 0, "byteOffset": 36, "byteLength": 48],
                ["buffer": 0, "byteOffset": 84, "byteLength": 6],
            ],
            "buffers": [["byteLength": bin.count]],
        ]
        return try TestGLB.writeTemp(TestGLB.serialize(json: json, bin: bin), prefix: "metal-draw-order")
    }

    private var view: simd_float4x4 {
        var view = matrix_identity_float4x4
        view.columns.3 = SIMD4(0, 0, -5, 1)
        return view
    }

    @Test func drawsFollowKhronosGroupingAndCentroidDepth() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let scene = try await MetalSceneLoader.load(url: url, device: device)
        try #require(scene.draws.map(\.nodeIndex) == Array(0..<9))
        // The centroid averages the indexed vertices only, before any vertex splitting.
        #expect(simd_distance(scene.draws[7].centroid, SIMD3(0, -1.0 / 3, -10)) < 1e-6)

        var lists = MetalDrawLists(draws: scene.draws)
        #expect(lists.opaque == [1, 6])
        #expect(lists.transmission == [4, 5])
        #expect(lists.transparent == [0, 2, 3, 7, 8])

        let frame = lists.frame(draws: scene.draws, view: view)
        // Prepass: opaque, then every transparent drawable far to near (no behind-camera filter).
        #expect(frame.transmissionPrepass == [1, 6, 7, 2, 8, 0, 3])
        // Main: opaque, transmission far to near, transparent far to near; depth > 0 is skipped.
        // Equal depths (2 and 8) keep their order: the sort is stable.
        #expect(frame.main == [1, 6, 5, 4, 7, 2, 8, 0])
        #expect(lists.frame(draws: scene.draws, view: view) == frame)
    }

    @Test func sceneWithoutTransmissionSkipsThePrepass() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let scene = try await MetalSceneLoader.load(url: TestFixtures.cube, device: device)
        var lists = MetalDrawLists(draws: scene.draws)
        let frame = lists.frame(draws: scene.draws, view: view)
        #expect(frame.transmissionPrepass == nil)
        #expect(frame.main == Array(scene.draws.indices))
    }
}
