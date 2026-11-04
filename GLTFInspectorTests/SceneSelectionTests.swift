import Foundation
import GLTFCore
import Renderer
import simd
import Testing
@testable import Renderer

/// Scene choice: `ViewOptions.sceneIndex` is an optional real scene index (nil = file default),
/// so scene 0 can be chosen even when the file's default scene is another one.
@MainActor
@Suite(.serialized)
struct SceneSelectionTests {
    /// A temporary copy of the cameras fixture with `edit` applied to its JSON.
    private func fixture(_ edit: (inout [String: Any]) -> Void) throws -> URL {
        let data = try Data(contentsOf: TestFixtures.cameras)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&json)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scene-selection-\(UUID()).gltf")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        return url
    }

    @Test func sceneZeroCanBeSelectedWhenDefaultSceneIsOne() async throws {
        let url = try fixture { json in
            var nodes = json["nodes"] as! [[String: Any]]
            nodes.append(["name": "Other", "mesh": 0, "translation": [10, 0, 0]])
            json["nodes"] = nodes
            json["scenes"] = [["nodes": [0]], ["nodes": [3]]]
            json["scene"] = 1
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(url, options: ViewOptions(sceneIndex: 1))
        #expect(view.renderer.scene?.draws.map(\.nodeIndex) == [3])
        try await view.apply(ViewOptions(sceneIndex: 0))
        #expect(view.renderer.scene?.draws.map(\.nodeIndex) == [0])
    }

    @Test func fileDefaultSceneIsDrawnWhenNoSceneIsChosen() async throws {
        let url = try fixture { json in
            var nodes = json["nodes"] as! [[String: Any]]
            nodes.append(["name": "Other", "mesh": 0, "translation": [10, 0, 0]])
            json["nodes"] = nodes
            json["scenes"] = [["nodes": [0]], ["nodes": [3]]]
            json["scene"] = 1
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(url, options: ViewOptions())
        #expect(view.options.sceneIndex == nil)
        #expect(view.renderer.scene?.draws.map(\.nodeIndex) == [3])
    }

    @Test func eachSceneFramesItsOwnBounds() async throws {
        let url = try fixture { json in
            var nodes = json["nodes"] as! [[String: Any]]
            nodes.append(["name": "Other", "mesh": 0, "translation": [10, 0, 0]])
            json["nodes"] = nodes
            json["scenes"] = [["nodes": [0]], ["nodes": [3]]]
            json["scene"] = 1
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(url, options: ViewOptions(sceneIndex: 0))
        let first = try #require(view.renderer.scene).accessorExtents(sceneIndex: 0)
        try await view.apply(ViewOptions(sceneIndex: 1))
        let second = try #require(view.renderer.scene).accessorExtents(sceneIndex: 1)
        #expect(first.min != second.min || first.max != second.max)
        #expect(second.min.x > first.max.x, "scene 1 sits at x = 10, beyond scene 0")
    }
}
