import simd
import Testing
@testable import GLTFCore
@testable import Renderer

@MainActor
@Suite(.serialized)
struct SkeletonOverlayTests {
    private func segments(_ vertices: [MetalLineVertex]) -> [(SIMD3<Float>, SIMD3<Float>)] {
        stride(from: 0, to: vertices.count - vertices.count % 2, by: 2).map {
            let a = vertices[$0].position, b = vertices[$0 + 1].position
            return (SIMD3(a.x, a.y, a.z), SIMD3(b.x, b.y, b.z))
        }
    }

    private func color(_ vertex: MetalLineVertex) -> SIMD3<Float> {
        SIMD3(vertex.color.x, vertex.color.y, vertex.color.z)
    }

    private let accent = SIMD3<Float>(0.15, 0.75, 1)
    private let muted = SIMD3<Float>(0.45, 0.45, 0.45)

    @Test func jointNodeIndicesMatchJSONJointOrder() {
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "skins": [["name": "Arm", "joints": [4, 5]]],
            "nodes": (0..<6).map { _ in ["name": "N"] as [String: Any] },
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ])
        #expect(document.skins[0].jointNodeIndices == [4, 5])
    }

    @Test func nearestJointAncestorSkipsNonJointNodes() {
        let parents = [-1, 0, 1, 2]
        let joints: Set<Int> = [1, 3]
        #expect(nearestJointAncestor(of: 3, jointSet: joints, nodeParents: parents) == 1)
        #expect(nearestJointAncestor(of: 2, jointSet: joints, nodeParents: parents) == 1)
        #expect(nearestJointAncestor(of: 1, jointSet: joints, nodeParents: parents) == nil)
    }

    @Test func selectingSkinDrawsSkeletonWithoutSceneNodeSelection() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.rigged)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedSkinIndex: 0))
        let hip = SIMD3<Float>(0, 0, 0), knee = SIMD3<Float>(0, 1, 0)
        #expect(segments(vertices).contains { a, b in
            (simd_distance(a, hip) < 1e-5 && simd_distance(b, knee) < 1e-5)
                || (simd_distance(b, hip) < 1e-5 && simd_distance(a, knee) < 1e-5)
        })
        #expect(vertices.allSatisfy { simd_length(color($0) - muted) < 0.02 })
    }

    @Test func noSkeletonWithoutSkinOrJointSelection() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.rigged)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 0))
        let hip = SIMD3<Float>(0, 0, 0)
        #expect(!vertices.contains { simd_distance(SIMD3($0.position.x, $0.position.y, $0.position.z), hip) < 1e-5 })
    }

    @Test func selectedJointHighlightsWithAccentColor() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.rigged)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 2))
        let accentCount = vertices.filter { simd_length(color($0) - accent) < 0.02 }.count
        let mutedCount = vertices.filter { simd_length(color($0) - muted) < 0.02 }.count
        #expect(accentCount >= 3, "the selected knee cross and bone use the accent colour")
        #expect(mutedCount >= 3, "the unselected hip cross stays muted grey")
    }

    @Test func hiddenJointSubtreeOmitsSkeletonLines() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.rigged)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(
            scene: scene,
            options: MetalOverlayOptions(selectedSkinIndex: 0, hiddenNodeIndices: [1])
        )
        let hip = SIMD3<Float>(0, 0, 0)
        #expect(!vertices.contains { simd_distance(SIMD3($0.position.x, $0.position.y, $0.position.z), hip) < 1e-5 })
    }

    @Test func boneSkipsNonJointAncestorInHierarchy() async throws {
        let url = try writeTempSkinWithPivotGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedSkinIndex: 0))
        let hip = SIMD3<Float>(0, 0, 0), pivot = SIMD3<Float>(0, 0.5, 0), knee = SIMD3<Float>(0, 1, 0)
        #expect(segments(vertices).contains { a, b in
            (simd_distance(a, hip) < 1e-5 && simd_distance(b, knee) < 1e-5)
                || (simd_distance(b, hip) < 1e-5 && simd_distance(a, knee) < 1e-5)
        })
        #expect(!segments(vertices).contains { a, b in
            simd_distance(a, pivot) < 1e-5 || simd_distance(b, pivot) < 1e-5
        })
    }
}
