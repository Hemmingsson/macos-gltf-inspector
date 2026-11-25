import Foundation
import GLTFCore
import simd
import Testing
@testable import GLTFInspector
@testable import Renderer

@MainActor
struct MaterialHighlightTests {
    private static let aabbVertexCount = 24

    @Test func defaultOverlayOptionsHaveNoMaterialHighlights() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cube)
        let scene = try #require(renderer.scene)
        #expect(overlayVertices(scene: scene, options: MetalOverlayOptions()).isEmpty)
    }

    @Test func highlightedNodesDrawOneAABBEach() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cube)
        let scene = try #require(renderer.scene)
        let base = overlayVertices(scene: scene, options: MetalOverlayOptions()).count
        let highlighted = overlayVertices(
            scene: scene,
            options: MetalOverlayOptions(highlightedNodeIndices: [0])
        )
        #expect(highlighted.count == base + Self.aabbVertexCount)
        let muted = highlighted.suffix(Self.aabbVertexCount).map(\.color)
        #expect(muted.allSatisfy { $0.x < 0.5 && $0.y < 0.75 })
    }

    @Test func materialHighlightBoxesOnlyTheNodesOwnPrimitives() async throws {
        let url = try writeTempDualMaterialParentChildGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let scene = try #require(renderer.scene)
        let subtree = try #require(scene.bounds(ofNode: 0))
        let own = try #require(scene.bounds(ofNode: 0, usingMaterial: 0))
        #expect(subtree.max.x - subtree.min.x > own.max.x - own.min.x + 1)
        func maxX(_ vertices: [MetalLineVertex]) -> Float {
            vertices.map(\.position.x).max() ?? -.infinity
        }
        let subtreeOverlay = overlayVertices(
            scene: scene,
            options: MetalOverlayOptions(highlightedNodeIndices: [0])
        )
        let ownOverlay = overlayVertices(
            scene: scene,
            options: MetalOverlayOptions(highlightedNodeIndices: [0], materialHighlightMaterialIndex: 0)
        )
        #expect(maxX(ownOverlay) < maxX(subtreeOverlay) - 1)
    }

    @Test func selectedNodeDoesNotDuplicateMaterialHighlightBox() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cube)
        let scene = try #require(renderer.scene)
        let selectedOnly = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 0))
        let selectedAndHighlighted = overlayVertices(
            scene: scene,
            options: MetalOverlayOptions(selectedNode: 0, highlightedNodeIndices: [0])
        )
        #expect(selectedOnly.count == selectedAndHighlighted.count)
    }

    private func cameraFixture(_ edit: (inout [String: Any]) -> Void) throws -> URL {
        var json = try GLBBox.peekDocumentJSON(from: TestFixtures.cameras)
        edit(&json)
        return try TestGLB.writeTempGLB(json: json, prefix: "material-highlight")
    }

    @Test func highlightSkipsMeshOutsideTheLoadedScene() async throws {
        let url = try cameraFixture { json in
            json["scenes"] = [["nodes": [1, 2]], ["nodes": [0]]]
            json["scene"] = 0
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let scene = try #require(renderer.scene)
        let highlighted = overlayVertices(
            scene: scene,
            options: MetalOverlayOptions(highlightedNodeIndices: [0])
        )
        #expect(highlighted.isEmpty)
    }

    @Test func highlightSkipsHiddenAndSoloedOutNodes() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cube)
        let scene = try #require(renderer.scene)
        let hidden = overlayVertices(
            scene: scene,
            options: MetalOverlayOptions(highlightedNodeIndices: [0], hiddenNodeIndices: [0])
        )
        #expect(hidden.isEmpty)
        let soloedOut = overlayVertices(
            scene: scene,
            options: MetalOverlayOptions(highlightedNodeIndices: [0], soloNodeIndices: [99])
        )
        #expect(soloedOut.isEmpty)
    }

    @Test func highlightSkipsMeshUnderAuthoredHiddenParent() async throws {
        let url = try cameraFixture { json in
            var nodes = json["nodes"] as! [[String: Any]]
            nodes[0]["extensions"] = ["KHR_node_visibility": ["visible": false]]
            json["nodes"] = nodes
            json["extensionsUsed"] = ["KHR_node_visibility"]
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let scene = try #require(renderer.scene)
        let highlighted = overlayVertices(
            scene: scene,
            options: MetalOverlayOptions(highlightedNodeIndices: [0])
        )
        #expect(highlighted.isEmpty)
    }
}
