import Foundation
import GLTFCore
@testable import GLTFInspector
import Testing

/// Outliner glyph mapping: home scene, shared mesh, material swatch, animation stopwatch.
struct OutlinerGlyphTests {
    private func showcase() throws -> GLTFDocument {
        let url = TestFixtures.fixture("ui-showcase.glb")
        return GLTFDocumentJSON.makeDocument(json: try GLBBox.peekDocumentJSON(from: url), fileURL: url)
    }

    @Test func defaultSceneUsesHouseAndOthersKeepStack() throws {
        let document = try showcase()
        #expect(document.systemImage(for: NodeID(kind: .scene, index: document.defaultSceneIndex)) == "house")
        let other = document.scenes.indices.first { $0 != document.defaultSceneIndex }
        if let other {
            #expect(document.systemImage(for: NodeID(kind: .scene, index: other)) == "square.stack.3d.up")
        }
    }

    @Test func animationUsesStopwatch() throws {
        let document = try showcase()
        #expect(!document.animations.isEmpty)
        #expect(document.systemImage(for: NodeID(kind: .animation, index: 0)) == "stopwatch")
    }

    @Test func sharedMeshUsesComponentGlyph() throws {
        let document = try showcase()
        let refs = document.meshReferenceCounts()
        let shared = try #require(refs.first { $0.value > 1 }?.key)
        let node = try #require(document.nodes.first { $0.meshIndex == shared })
        #expect(
            document.assetImage(for: NodeID(kind: .mesh, index: node.index), meshRefs: refs)
                == SplineIcons.sharedMesh
        )
    }

    @Test func materialsProvideBaseColorSwatches() throws {
        let document = try showcase()
        #expect(document.materials.count >= 2)
        #expect(document.materials[0].baseColorFactor != nil)
        #expect(document.swatchColor(for: NodeID(kind: .material, index: 0)) != nil)
        #expect(document.swatchColor(for: NodeID(kind: .material, index: 1)) != nil)
        #expect(document.assetImage(for: NodeID(kind: .material, index: 0)) == nil)
    }
}
