import Foundation
@testable import GLTFCore
import Testing
@testable import GLTFInspector
@testable import RendererWebKit

struct WebRendererLoadCopyTests {
    @Test func texturesWinTheHeadline() {
        let inventory = WebRendererAssetInventory(
            imageCount: 45,
            textureCount: 45,
            meshCount: 12,
            materialCount: 8,
            triangleCount: 80_000
        )
        #expect(WebRendererLoadCopy.message(for: inventory) == "Loading 45 textures…")
        #expect(WebRendererLoadCopy.detail(for: inventory) == "12 meshes · 80k triangles · 8 materials · 45 textures")
    }

    @Test func singularTexture() {
        let inventory = WebRendererAssetInventory(
            imageCount: 1,
            textureCount: 1,
            meshCount: 1,
            materialCount: 1,
            triangleCount: 12
        )
        #expect(WebRendererLoadCopy.message(for: inventory) == "Loading 1 texture…")
        #expect(WebRendererLoadCopy.detail(for: inventory) == "1 mesh · 12 triangles · 1 material · 1 texture")
    }

    @Test func meshesWhenThereAreNoRasters() {
        let inventory = WebRendererAssetInventory(
            imageCount: 0,
            textureCount: 0,
            meshCount: 3,
            materialCount: 1,
            triangleCount: 36
        )
        #expect(WebRendererLoadCopy.message(for: inventory) == "Loading 3 meshes…")
        #expect(WebRendererLoadCopy.detail(for: inventory) == "3 meshes · 36 triangles · 1 material")
    }

    @Test func missingInventoryIsGeneric() {
        #expect(WebRendererLoadCopy.message(for: nil) == WebRendererLoadCopy.model)
        #expect(WebRendererLoadCopy.detail(for: nil) == nil)
    }

    @Test func drawingPhaseIsExplicit() {
        #expect(WebRendererLoadCopy.drawing == "Drawing first frame…")
    }

    @Test func peekReadsSidecarAndGLBHeader() throws {
        let cube = try #require(WebRendererAssetInventory.peek(from: TestFixtures.cube))
        #expect(cube.meshCount >= 1)
        #expect(WebRendererLoadCopy.message(for: cube) != WebRendererLoadCopy.starting)

        let tiny = try #require(WebRendererAssetInventory.peek(from: TestFixtures.tiny))
        #expect(tiny.meshCount >= 1)
        #expect(try GLBBox.peekDocumentJSON(from: TestFixtures.tiny)["asset"] != nil)
        #expect(try GLBBox.peekDocumentJSON(from: TestFixtures.cube)["asset"] != nil)
    }
}
