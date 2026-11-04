import simd
import Testing
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
}
