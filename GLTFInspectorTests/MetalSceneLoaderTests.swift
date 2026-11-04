import Foundation
import Metal
import simd
import Testing
@testable import Renderer

struct MetalSceneLoaderTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    @Test(arguments: [TestFixtures.tiny, TestFixtures.cube, TestFixtures.rigged, TestFixtures.morph])
    func fixtureContainsFiniteGeometry(url: URL) async throws {
        let scene = try await MetalSceneLoader.load(url:url,device:device())
        #expect(!scene.draws.isEmpty)
        #expect(scene.boundsMin.x.isFinite && scene.boundsMax.x.isFinite)
        #expect(all(scene.boundsMin .<= scene.boundsMax))
        for draw in scene.draws {
            #expect(draw.indexCount > 0)
            #expect(draw.vertexBuffer.length % MemoryLayout<MetalVertex>.stride == 0)
            #expect(draw.indexBuffer.length == draw.indexCount * 4)
        }
    }

    @Test func selectedSceneChangesDrawnNodes() async throws {
        let gpu = try device()
        let first = try await MetalSceneLoader.load(url:TestFixtures.multiScene,device:gpu,sceneIndex:0)
        let second = try await MetalSceneLoader.load(url:TestFixtures.multiScene,device:gpu,sceneIndex:1)
        #expect(first.draws.map(\.nodeIndex) == [0])
        #expect(second.draws.map(\.nodeIndex) == [1])
        await #expect(throws:(any Error).self) {
            _ = try await MetalSceneLoader.load(url:TestFixtures.multiScene,device:gpu,sceneIndex:999)
        }
    }

    @Test func corruptFileIsRejected() async throws {
        let gpu = try device()
        await #expect(throws:(any Error).self) {
            _ = try await MetalSceneLoader.load(url:TestFixtures.corrupt,device:gpu)
        }
    }

    @Test func authoredMorphWeightIsAppliedAtRest() async throws {
        let data = try Data(contentsOf:TestFixtures.morph)
        var json = try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
        var meshes = try #require(json["meshes"] as? [[String:Any]])
        meshes[0]["weights"] = [0.5]
        json["meshes"] = meshes
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("metal-morph-\(UUID())")
        try FileManager.default.copyItem(at: TestFixtures.morph.deletingLastPathComponent(), to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(TestFixtures.morph.lastPathComponent)
        try JSONSerialization.data(withJSONObject:json, options: .withoutEscapingSlashes).write(to:url)
        defer { try? FileManager.default.removeItem(at:url) }
        let scene = try await MetalSceneLoader.load(url:url,device:device())
        #expect(abs(scene.boundsMax.z - 0.5) < 0.0001)
    }

    @Test func generatedTangentsAreFiniteAndPerpendicular() async throws {
        let scene = try await MetalSceneLoader.load(url:TestFixtures.cube,device:device())
        for draw in scene.draws {
            let count = draw.vertexBuffer.length / MemoryLayout<MetalVertex>.stride
            let vertices = draw.vertexBuffer.contents().bindMemory(to:MetalVertex.self,capacity:count)
            for i in 0..<count {
                let n = vertices[i].normal
                let t = vertices[i].tangent
                #expect(t.x.isFinite && t.y.isFinite && t.z.isFinite)
                #expect(abs(n.x*t.x+n.y*t.y+n.z*t.z) < 0.001)
                #expect(abs(t.w) == 1)
            }
        }
    }

    @Test func packedVertexMatchesMSLLayout() {
        #expect(MemoryLayout<MetalVertex>.stride == 80)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.normal) == 16)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.tangent) == 32)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.color) == 48)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.uv0) == 64)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.uv1) == 72)
    }
}
