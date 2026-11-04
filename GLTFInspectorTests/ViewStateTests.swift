import Foundation
import GLTFCore
import Testing
@testable import GLTFInspector
import Renderer

/// A window's view state: what follows Settings, what the window owns, and what reaches the
/// renderer.
@MainActor
struct ViewStateTests {
    private func settings() throws -> AppSettings {
        let suite = "gltf.view-state.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    /// Untouched stage values track Settings live; a value changed in the window stays put.
    @Test func stageFollowsSettingsUntilTheWindowChangesIt() throws {
        let settings = try settings()
        let view = ViewState(settings: settings)
        let other = ViewState(settings: settings)
        settings.backdrop = .dark
        #expect(view.backdrop == .dark && other.backdrop == .dark)

        other.backdrop = .white
        settings.backdrop = .window
        #expect(view.backdrop == .window)
        #expect(other.backdrop == .white)
        #expect(settings.backdrop == .window, "a window never writes Settings")

        other.reset()
        #expect(other.backdrop == .window)
    }

    @Test func fieldOfViewStaysInRange() throws {
        let view = ViewState(settings: try settings())
        view.fieldOfView = 5
        #expect(view.fieldOfView == ViewState.fieldOfViewRange.lowerBound)
        view.fieldOfView = 200
        #expect(view.fieldOfView == ViewState.fieldOfViewRange.upperBound)
    }

    /// A file that drops a mode (no triangles: no wireframe) never leaves the window on it.
    @Test func viewModeIsAlwaysOneTheFileOffers() throws {
        let view = ViewState(settings: try settings())
        view.viewModes = [.shaded, .wireframe]
        view.viewMode = .wireframe
        view.viewModes = [.shaded]
        #expect(view.viewMode == .shaded)
    }

    /// A new document starts from Settings' lighting, not the previous document's.
    @Test func resetRestoresSettingsLightingAndNeutralCamera() throws {
        let settings = try settings()
        settings.environment = .field
        settings.toneMapping = .acesHill
        let view = ViewState(settings: settings)
        view.environment = .colorfulStudio
        view.toneMapping = .none
        view.exposure = 1.5
        view.environmentYaw = 90
        view.isOrthographic = true
        view.fieldOfView = 60

        view.reset()
        #expect(view.environment == .field && view.toneMapping == .acesHill)
        #expect(view.exposure == 0 && view.environmentYaw == 0)
        #expect(!view.isOrthographic && view.fieldOfView == ViewState.defaultFieldOfView)
    }

    /// Changing scene drops a node selection and the file camera (both belong to the old scene)
    /// but keeps a material selection.
    @Test func sceneChangeDropsSceneNodeSelectionAndFileCamera() throws {
        let view = ViewState(settings: try settings())
        view.selection = NodeID(kind: .mesh, index: 0)
        view.fileCameraNodeIndex = 3
        view.sceneIndex = 1
        #expect(view.selection == nil && view.fileCameraNodeIndex == nil)

        view.selection = NodeID(kind: .material, index: 2)
        view.sceneIndex = 0
        #expect(view.selection == NodeID(kind: .material, index: 2))
    }

    /// Only mesh and group nodes are outlined on the canvas; a material row is not a node.
    @Test func onlySceneMeshesAndGroupsReachTheCanvasHighlight() throws {
        let view = ViewState(settings: try settings())
        view.selection = NodeID(kind: .mesh, index: 4)
        #expect(view.options.selectedNodeIndex == 4)
        view.selection = NodeID(kind: .material, index: 4)
        #expect(view.options.selectedNodeIndex == nil)
        view.selection = NodeID(kind: .camera, index: 4)
        #expect(view.options.selectedNodeIndex == nil)
    }

    @Test func materialHighlightFollowsVariantMappings() throws {
        let view = ViewState(settings: try settings())
        view.document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "extensions": ["KHR_materials_variants": ["variants": [["name": "Alt"]]]],
            "accessors": [["componentType": 5126, "count": 3, "type": "VEC3"]],
            "materials": [["name": "Base"], ["name": "Alt"]],
            "meshes": [[
                "primitives": [[
                    "attributes": ["POSITION": 0],
                    "material": 0,
                    "extensions": ["KHR_materials_variants": ["mappings": [
                        ["variants": [0], "material": 1],
                    ]]],
                ]],
            ]],
            "nodes": [["name": "Mesh", "mesh": 0]],
            "scenes": [["nodes": [0]]],
        ])
        view.materialVariantIndex = 0
        view.selection = NodeID(kind: .material, index: 1)
        #expect(view.options.highlightedNodeIndices == [0])
        view.selection = NodeID(kind: .material, index: 0)
        #expect(view.options.highlightedNodeIndices.isEmpty)
    }

    @Test func hiddenNodesAreOmittedFromMaterialHighlights() throws {
        let view = ViewState(settings: try settings())
        view.document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "accessors": [["componentType": 5126, "count": 3, "type": "VEC3"]],
            "materials": [["name": "Shared"]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
            "nodes": [["name": "A", "mesh": 0], ["name": "B", "mesh": 0]],
            "scenes": [["nodes": [0, 1]]],
        ])
        view.selection = NodeID(kind: .material, index: 0)
        view.toggleHidden(0)
        #expect(view.options.highlightedNodeIndices == [1])
    }

    @Test func materialSelectionHighlightsEveryUserNode() throws {
        let view = ViewState(settings: try settings())
        view.document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "accessors": [["componentType": 5126, "count": 3, "type": "VEC3"]],
            "materials": [["name": "Shared"], ["name": "Lonely"]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
            "nodes": [["name": "A", "mesh": 0], ["name": "B", "mesh": 0]],
            "scenes": [["nodes": [0, 1]]],
        ])
        view.selection = NodeID(kind: .material, index: 0)
        #expect(view.options.highlightedNodeIndices == [0, 1])
        view.selection = NodeID(kind: .material, index: 1)
        #expect(view.options.highlightedNodeIndices.isEmpty)
        view.selection = NodeID(kind: .mesh, index: 0)
        #expect(view.options.highlightedNodeIndices.isEmpty)
    }

    @Test func hideAndSoloReachTheRendererOptions() throws {
        let view = ViewState(settings: try settings())
        view.toggleHidden(2)
        view.toggleHidden(5)
        view.toggleHidden(5)
        #expect(view.options.hiddenNodeIndices == [2])

        view.toggleSolo(4)
        #expect(view.soloNodes == [4] && view.options.soloNodeIndices == [4])
        view.toggleSolo(7)
        #expect(view.soloNodes == [7])
        view.toggleSolo(7)
        #expect(view.soloNodes.isEmpty)
    }

    @Test func showAllAndResetClearHiddenAndSoloNodes() throws {
        let view = ViewState(settings: try settings())
        view.toggleHidden(1)
        view.toggleSolo(3)
        view.showAll()
        #expect(view.hiddenNodes.isEmpty && view.soloNodes.isEmpty)

        view.toggleHidden(1)
        view.toggleSolo(3)
        view.reset()
        #expect(view.hiddenNodes.isEmpty && view.soloNodes.isEmpty)
    }

    @Test func sceneChangeClearsHiddenAndSoloNodes() throws {
        let view = ViewState(settings: try settings())
        view.toggleHidden(1)
        view.toggleSolo(3)
        view.sceneIndex = 1
        #expect(view.hiddenNodes.isEmpty && view.soloNodes.isEmpty)
    }

    @Test func optionsCarryTheWindowsLook() throws {
        let view = ViewState(settings: try settings())
        view.exposure = 0.5
        view.environmentYaw = 45
        view.environment = .field
        view.backdrop = .dark
        view.isOrthographic = true
        view.materialVariantIndex = 1
        let options = view.options
        #expect(options.look.exposureEV == 0.5 && options.look.environmentYawDegrees == 45)
        #expect(options.look.environment == .field)
        #expect(options.look.background == BackdropStyle.dark.color)
        #expect(options.isOrthographic && options.materialVariantIndex == 1)
    }

    /// A file camera clears the canned angle; a preset needs a drawn model to act on.
    /// Shift-click range: primary is the far end in outliner order, not the first empty by kind name.
    @Test func shiftRangePrimaryIsTheFarEndInOutlinerOrder() throws {
        let view = ViewState(settings: try settings())
        view.document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "scenes": [["nodes": [0]]],
            "nodes": [["name": "Root", "children": [1, 3]],
                      ["name": "Group", "children": [2]],
                      ["name": "Mesh A", "mesh": 0], ["name": "Mesh B", "mesh": 0]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
            "accessors": [["componentType": 5126, "count": 3, "type": "VEC3"]],
            "materials": [["name": "Shared"]],
        ])
        let meshA = NodeID(kind: .mesh, index: 2)
        let meshB = NodeID(kind: .mesh, index: 3)
        let root = NodeID(kind: .empty, index: 0)
        let group = NodeID(kind: .empty, index: 1)
        view.selection = meshA
        view.selectedIDs = [root, group, meshA, meshB]
        #expect(view.selection == meshB)

        view.selection = meshB
        view.selectedIDs = [root, group, meshA, meshB]
        #expect(view.selection == meshA)
    }

    @Test func resetClearsSceneGizmosAndPickMemory() throws {
        let view = ViewState(settings: try settings())
        view.document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "scenes": [["nodes": [0, 1]]],
            "nodes": [["name": "A", "mesh": 0], ["name": "B", "mesh": 0]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
            "accessors": [["componentType": 5126, "count": 3, "type": "VEC3"]],
            "materials": [["name": "M"]],
        ])
        view.showsSceneGizmos = true
        view.pick(0)
        view.pick(0)
        view.reset()
        #expect(!view.showsSceneGizmos)
        view.pick(0)
        #expect(view.selection == NodeID(kind: .mesh, index: 0))
    }

    @Test func fileCameraClearsTheActivePreset() throws {
        let view = ViewState(settings: try settings())
        view.show(.front)
        #expect(view.activeCameraPreset == .front)
        view.fileCameraNodeIndex = 1
        #expect(view.activeCameraPreset == nil)
    }
}
