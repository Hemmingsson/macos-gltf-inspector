import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct ModelDimensionsTests {
    @Test func readoutFormatsMetersWHD() {
        let bounds = BoundingBox(min: SIMD3(0, 0, 0), max: SIMD3(1.24, 0.86, 1.10))
        let dims = ModelDimensions(bounds: bounds)
        #expect(dims?.width == 1.24)
        #expect(dims?.height == 0.86)
        #expect(dims?.depth == 1.10)
        #expect(dims?.readout == "1.24 × 0.86 × 1.10 m")
    }

    @Test func emptyBoundsReturnsNil() {
        #expect(ModelDimensions(bounds: BoundingBox()) == nil)
    }

    @Test @MainActor func cubeMatchesLoggedUnitExtent() async throws {
        let url = TestFixtures.cube
        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        let dims = PreviewCamera.dimensions(of: model.entity, relativeTo: model.entity)
        #expect(dims != nil)
        guard let dims else { return }
        // Authored accessor min/max are ±0.5 → 1 m cube; matches former extent log.
        #expect(abs(dims.width - 1) < 0.02)
        #expect(abs(dims.height - 1) < 0.02)
        #expect(abs(dims.depth - 1) < 0.02)
        #expect(dims.readout == "1.00 × 1.00 × 1.00 m")
    }
}
