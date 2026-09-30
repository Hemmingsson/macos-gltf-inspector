import Foundation
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

/// `ModelBounds.from(json:)` (accessor min/max × node transforms) against the entity-derived
/// bounds the RealityKit canvas frames (`PreviewCamera.modelBounds` after convert).
struct JSONModelBoundsRealityKitTests {
    /// Fixtures that do not load on purpose (see `GLTFValidatorCorpusTests.expectedErrors`).
    static let unloadable: Set<String> = [
        "invalid/unresolved-mesh.gltf",
        "corrupt/truncated.glb",
    ]

    static var models: [(name: String, url: URL)] {
        let root = TestFixtures.url("TestModels/Fixture Models").path + "/"
        let fixtures = GLTFValidatorCorpusTests.fixtures.map { url in
            (name: url.path.replacingOccurrences(of: root, with: ""), url: url)
        }
        let samples = ((try? PixelDiffManifest.load())?.entries ?? []).map { (name: $0.name, url: $0.modelURL) }
        return fixtures.filter { !unloadable.contains($0.name) } + samples
    }

    @Test @MainActor func jsonBoundsMatchEntityBounds() async throws {
        let models = Self.models
        #expect(models.count >= 30, "found only \(models.count) models; fetch the pinned samples")
        var report: [String] = []
        for (name, url) in models {
            let json = try GLBBox.peekDocumentJSON(from: url)
            let fromJSON = ModelBounds.from(json: json)
            let model = try await EntityLoader.load(from: url, includeAnimations: false)
            let entityBox = PreviewCamera.modelBounds(of: model.entity, relativeTo: model.entity)
            guard let fromJSON, !entityBox.isEmpty else {
                report.append("\(name): json=\(String(describing: fromJSON)) entityEmpty=\(entityBox.isEmpty)")
                continue
            }
            let scale = max(1e-4, simd_reduce_max(entityBox.max - entityBox.min))
            let error = max(
                simd_reduce_max(simd_abs(fromJSON.min - entityBox.min)),
                simd_reduce_max(simd_abs(fromJSON.max - entityBox.max))
            ) / scale
            // Largest seen on the pinned set: 6e-5 (TextureEncodingTest; accessor max is looser
            // than its vertices). Skinned / morph fixtures match at bind pose / base shape.
            if error > 1e-3 {
                report.append("\(name): relErr=\(error) json=\(fromJSON.size) entity=\(entityBox.max - entityBox.min)")
            }
        }
        #expect(report.isEmpty, "\(report.joined(separator: "\n"))")
    }
}
