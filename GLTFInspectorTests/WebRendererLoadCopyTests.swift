import Foundation
@testable import GLTFCore
import Testing
@testable import GLTFInspector

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
        #expect(WebRendererLoadCopy.detail(for: inventory) == "12 meshes · 80k triangles")
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
        #expect(WebRendererLoadCopy.detail(for: inventory) == "1 mesh · 12 triangles")
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
        #expect(WebRendererLoadCopy.detail(for: inventory) == nil)
    }

    @Test func missingInventoryIsGeneric() {
        #expect(WebRendererLoadCopy.message(for: nil) == WebRendererLoadCopy.model)
        #expect(WebRendererLoadCopy.detail(for: nil) == nil)
    }

    @Test func drawingPhaseIsExplicit() {
        #expect(WebRendererLoadCopy.drawing == "Drawing…")
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

struct WebRendererProgressEventTests {
    @Test func progressEventDoesNotCountAsMalformed() throws {
        let event = try #require(WebRendererEvent(body: [
            "event": "progress",
            "stage": "load",
        ] as [String: Any]))
        #expect(event.name == .progress)
        #expect(event.stage == "load")
    }
}
