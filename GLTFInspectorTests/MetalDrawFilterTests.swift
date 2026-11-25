import CoreGraphics
import Foundation
import Metal
import simd
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct MetalDrawFilterTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    /// Node 0 is a group (no mesh) with children 1 and 2; node 1 has child 3. Nodes 1, 2 and 3
    /// each draw the same triangle, so `scene.draws` holds them in visit order: 1, 3, 2.
    private func nestedGroupGLB() throws -> URL {
        let bin = floatTriangleBin()
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": bin.count]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
            "accessors": [[
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [0, 0, 0],
                "max": [1, 1, 0],
            ]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "nodes": [
                ["name": "Group", "children": [1, 2]],
                ["name": "Parent", "mesh": 0, "children": [3]],
                ["name": "Sibling", "mesh": 0],
                ["name": "Child", "mesh": 0],
            ],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ]
        return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "metal-draw-filter")
    }

    /// Node indices of the draws the filter keeps, sorted.
    private func drawnNodes(_ options: ViewOptions, in scene: MetalScene) -> [Int] {
        let mask = MetalDrawFilter(options).visibleDraws(in: scene)
        return zip(scene.draws, mask).filter { $0.1 }.map { $0.0.nodeIndex }.sorted()
    }

    @Test func ancestorsWalkFromTheNodeToTheRoot() async throws {
        let url = try nestedGroupGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        #expect(scene.nodeParents == [-1, 0, 0, 1])
        #expect(scene.ancestors(ofNode: 0) == [0])
        #expect(scene.ancestors(ofNode: 2) == [2, 0])
        #expect(scene.ancestors(ofNode: 3) == [3, 1, 0])
        #expect(scene.ancestors(ofNode: 9) == [])
        #expect(scene.ancestors(ofNode: -1) == [])
    }

    @Test func emptyFilterDrawsEverything() async throws {
        let url = try nestedGroupGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        #expect(MetalDrawFilter(ViewOptions()).isEmpty)
        #expect(MetalDrawFilter(ViewOptions()).visibleDraws(in: scene) == [true, true, true])
        #expect(drawnNodes(ViewOptions(), in: scene) == [1, 2, 3])
    }

    @Test func hidingANodeHidesItsSubtree() async throws {
        let url = try nestedGroupGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        #expect(drawnNodes(ViewOptions(hiddenNodeIndices: [0]), in: scene) == [])
        #expect(drawnNodes(ViewOptions(hiddenNodeIndices: [1]), in: scene) == [2])
        #expect(drawnNodes(ViewOptions(hiddenNodeIndices: [3]), in: scene) == [1, 2])
    }

    @Test func soloKeepsOnlyTheSubtreesOfTheSoloedNodes() async throws {
        let url = try nestedGroupGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        #expect(drawnNodes(ViewOptions(soloNodeIndices: [2]), in: scene) == [2])
        #expect(drawnNodes(ViewOptions(soloNodeIndices: [1]), in: scene) == [1, 3])
        #expect(drawnNodes(ViewOptions(hiddenNodeIndices: [3], soloNodeIndices: [1]), in: scene) == [1])
    }

    @Test func isolatingAMeshNodeDrawsOnlyItsOwnDraws() async throws {
        let url = try nestedGroupGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        #expect(drawnNodes(ViewOptions(isolatedNodeIndex: 1), in: scene) == [1])
        #expect(drawnNodes(ViewOptions(isolatedNodeIndex: 3), in: scene) == [3])
    }

    @Test func isolatingAGroupDrawsItsWholeSubtree() async throws {
        let url = try nestedGroupGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        #expect(drawnNodes(ViewOptions(isolatedNodeIndex: 0), in: scene) == [1, 2, 3])
    }

    @Test func lightsCarryTheirNodeIndex() async throws {
        let scene = try await MetalSceneLoader.load(url: TestFixtures.lights, device: device())
        #expect(scene.lights.count == 3)
        #expect(scene.lights.map(\.nodeIndex) == [0, 1, 2])
        #expect(scene.lights.allSatisfy { scene.nodeParents.indices.contains($0.nodeIndex) })
    }

    @Test func emptyFilterKeepsEveryLight() async throws {
        let scene = try await MetalSceneLoader.load(url: TestFixtures.lights, device: device())
        let kept = MetalDrawFilter(ViewOptions()).visibleLights(in: scene)
        #expect(kept.map(\.nodeIndex) == scene.lights.map(\.nodeIndex))
    }

    @Test func hidingALightsNodeRemovesThatLight() async throws {
        let scene = try await MetalSceneLoader.load(url: TestFixtures.lights, device: device())
        let kept = MetalDrawFilter(ViewOptions(hiddenNodeIndices: [1])).visibleLights(in: scene)
        #expect(kept.map(\.nodeIndex) == [0, 2])
    }

    @Test func soloAndIsolationLeaveLightsAlone() async throws {
        let scene = try await MetalSceneLoader.load(url: TestFixtures.lights, device: device())
        let options = ViewOptions(soloNodeIndices: [0], isolatedNodeIndex: 0)
        #expect(MetalDrawFilter(options).visibleLights(in: scene).count == 3)
    }

    @Test func hidingEveryMeshLeavesNoPixels() async throws {
        let url = try nestedGroupGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let pose = MetalCameraPose(azimuth: 0, elevation: 0, distance: 5, target: SIMD3(0.5, 0.5, 0),
                                   yfov: .pi / 3, znear: 0.1, zfar: 100)
        let shown = try renderer.image(ViewOptions(), pose: pose, width: 64, height: 64)
        #expect(alphaBytes(of: shown).contains { $0 > 0 }, "the triangle must cover pixels before hiding")
        let hidden = try renderer.image(ViewOptions(hiddenNodeIndices: [1, 2, 3]), pose: pose, width: 64, height: 64)
        #expect(alphaBytes(of: hidden).allSatisfy { $0 == 0 })
    }

    /// The alpha byte of every pixel (RGBA, alpha last, as `MetalRenderer.image` writes it).
    private func alphaBytes(of image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        return (0..<image.height).flatMap { y in
            (0..<image.width).map { x in bytes[y * image.bytesPerRow + x * 4 + 3] }
        }
    }
}
