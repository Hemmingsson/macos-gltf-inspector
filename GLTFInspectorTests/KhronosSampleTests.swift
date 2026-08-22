import Foundation
import RealityKit
import Testing
@testable import GLTFInspector

@MainActor
struct KhronosSampleTests {
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func boomBoxBindsAuthoredMaps() async throws {
        try #require(FileManager.default.fileExists(atPath: TestModels.boomBox.path))
        let loaded = try await EntityLoader.load(from: TestModels.boomBox, includeAnimations: false)
        #expect(loaded.convertProblems.errorCount == 0)
        let pbr = pbrMaterials(in: loaded.entity)
        try #require(!pbr.isEmpty)
        if loaded.document.materials.contains(where: { $0.maps.baseColor }) {
            #expect(pbr.contains { $0.baseColor.texture != nil })
        }
        if loaded.document.materials.contains(where: { $0.maps.normal }) {
            #expect(pbr.contains { $0.normal.texture != nil })
        }
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples), arguments: TestModels.khronosGLBs)
    func khronosSampleLoads(_ url: URL) async throws {
        let loaded = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(EntityLoader.modelComponentCount(in: loaded.entity) > 0)
    }
}
