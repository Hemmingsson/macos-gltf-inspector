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
}
