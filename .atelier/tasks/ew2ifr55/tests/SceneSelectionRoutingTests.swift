import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import Testing

@MainActor
struct SceneSelectionRoutingTests {
    private func model() async throws -> DocumentWindowModel {
        let suite = "gltf.selection-routing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let model = DocumentWindowModel(documentURL: nil, settings: AppSettings(defaults: defaults))
        let url = URL(fileURLWithPath: "/tmp/selection-routing.glb")
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "scenes": [["nodes": [0]]],
            "nodes": [["name": "Root", "children": [1, 3]],
                      ["name": "Group", "children": [2]],
                      ["name": "Mesh A", "mesh": 0], ["name": "Mesh B", "mesh": 0]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
            "accessors": [["componentType": 5126, "count": 3, "type": "VEC3"]],
            "materials": [["name": "Shared"], ["name": "Unused"]],
        ])
        guard case .started(let generation) = model.beginOpen(url) else {
            throw CocoaError(.fileReadUnknown)
        }
        await model.openSummary(url, generation: generation, load: { _ in document })
        return model
    }

    @Test func differentMeshHitStartsItsOwnSelection() async throws {
        let model = try await model()
        model.view.canvas.onPick?(2)
        model.view.canvas.onPick?(3)
        #expect(model.view.selection == NodeID(kind: .mesh, index: 3))
    }

    @Test func backgroundAndUnknownNodeClearSelection() async throws {
        let model = try await model()
        model.view.canvas.onPick?(2)
        model.view.canvas.onPick?(nil)
        #expect(model.view.selection == nil)
        model.view.canvas.onPick?(2)
        model.view.canvas.onPick?(99)
        #expect(model.view.selection == nil)
    }

    @Test func selectingAnUnusedMaterialAddsNoRendererHighlights() async throws {
        let model = try await model()
        let unselected = model.view.options
        model.view.selection = NodeID(kind: .material, index: 1)
        #expect(model.view.options == unselected)
    }

    // lusha0c3: repeated picks hit the same mesh while selection ascends.
    @Test func repeatedMeshHitsCycleThroughParentsAndBack() async throws {
        let model = try await model()
        model.view.canvas.onPick?(2)
        #expect(model.view.selection == NodeID(kind: .mesh, index: 2))
        model.view.canvas.onPick?(2)
        #expect(model.view.selection == NodeID(kind: .empty, index: 1))
        model.view.canvas.onPick?(2)
        #expect(model.view.selection == NodeID(kind: .empty, index: 0))
        model.view.canvas.onPick?(2)
        #expect(model.view.selection == NodeID(kind: .mesh, index: 2))
    }

    // g7bd2y5a: material users must reach the actual renderer options.
    @Test func selectingAUsedMaterialChangesRendererHighlightOptions() async throws {
        let model = try await model()
        let unselected = model.view.options
        model.view.selection = NodeID(kind: .material, index: 0)
        #expect(model.view.options != unselected)
        model.view.selection = nil
        #expect(model.view.options == unselected)
    }
}
