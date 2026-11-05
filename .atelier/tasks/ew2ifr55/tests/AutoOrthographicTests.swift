import Foundation
import Renderer
import Testing
@testable import GLTFInspector

@MainActor
struct AutoOrthographicTests {
    private func state() throws -> ViewState {
        let suite = "gltf.auto-orthographic.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return ViewState(settings: AppSettings(defaults: defaults))
    }

    // Backlog ggq8r9uj: the preset command is also the navigation gizmo's command seam.
    @Test(arguments: [CameraPreset.front, .back, .left, .right, .top, .bottom])
    func axisSnapEnablesOrthographicProjection(_ preset: CameraPreset) throws {
        let view = try state()
        view.show(preset)
        #expect(view.activeCameraPreset == preset)
        #expect(view.isOrthographic, "axis-aligned views must automatically use orthographic projection")
        #expect(view.options.isOrthographic, "the projection change must reach the renderer")
    }

    @Test func isometricSnapUsesPerspectiveAfterAnAxisSnap() throws {
        let view = try state()
        view.show(.top)
        view.show(.isometric)
        #expect(!view.isOrthographic)
    }

    @Test func resetClearsOrthographicProjection() throws {
        let view = try state()
        view.isOrthographic = true
        view.resetView()
        #expect(!view.options.isOrthographic)
    }
}
