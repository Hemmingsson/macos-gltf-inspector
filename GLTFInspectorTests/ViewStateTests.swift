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
    @Test func fileCameraClearsTheActivePreset() throws {
        let view = ViewState(settings: try settings())
        view.show(.front)
        #expect(view.activeCameraPreset == .front)
        view.fileCameraNodeIndex = 1
        #expect(view.activeCameraPreset == nil)
    }
}
