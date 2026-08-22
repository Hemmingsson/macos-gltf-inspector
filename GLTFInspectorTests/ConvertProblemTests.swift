import Foundation
import RealityKit
import Testing
@testable import GLTFInspector

@MainActor
struct ConvertProblemTests {
    @Test func cubeHasNoConvertProblems() async throws {
        try #require(TestFixtures.exists(TestFixtures.cube))
        let loaded = try await EntityLoader.load(from: TestFixtures.cube, includeAnimations: false)
        #expect(loaded.convertProblems.isEmpty)
        let model = EngineSceneModel(loaded: loaded, fileName: "cube.gltf")
        #expect(model.convertProblems.isEmpty)
    }

    @Test func missingTextureFixtureReportsError() async throws {
        try #require(TestFixtures.exists(TestFixtures.missingTexture))
        let loaded = try await EntityLoader.load(from: TestFixtures.missingTexture, includeAnimations: false)
        #expect(EntityLoader.modelComponentCount(in: loaded.entity) > 0)
        #expect(loaded.convertProblems.items.contains { $0.code == .missingTexture })
        let model = EngineSceneModel(loaded: loaded, fileName: "missing-image.gltf")
        #expect(model.convertProblems.entries.contains { $0.code == ConvertProblem.Code.missingTexture.rawValue })
        #expect(model.convertProblems.errorCount >= 1)
    }

    @Test func mixedTrianglesAndLinesRecordsDroppedPrimitive() async throws {
        let url = try GLBBox.writePrepared(try mixedTrianglesAndLinesGLB(), prefix: "mixed-prim")
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(EntityLoader.modelComponentCount(in: loaded.entity) > 0)
        #expect(loaded.convertProblems.items.contains { $0.code == .droppedPrimitive })
    }

    @Test func mapConvertProblemsCopiesCode() {
        var report = ConvertProblemReport()
        report.append(
            .missingTexture,
            severity: .error,
            message: "Texture did not load",
            materialName: "Wood"
        )
        let list = EngineSceneModel.mapConvertProblems(report)
        #expect(list.entries.count == 1)
        #expect(list.entries[0].code == "missingTexture")
        #expect(list.entries[0].severity == .error)
    }
}
