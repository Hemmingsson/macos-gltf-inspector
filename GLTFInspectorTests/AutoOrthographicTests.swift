import AppKit
import Foundation
import Testing
@testable import GLTFInspector
@testable import Renderer

@MainActor
struct AutoOrthographicTests {
    private func state() throws -> ViewState {
        let suite = "gltf.auto-orthographic.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return ViewState(settings: AppSettings(defaults: defaults))
    }

    private func readyView() async throws -> ViewState {
        let view = try state()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        view.canvas.mount(in: container, url: TestFixtures.cube, options: view.options)
        try #require(try await waitUntil { view.canvas.phase == .ready })
        return view
    }

    // Backlog ggq8r9uj: the preset command is also the navigation gizmo's command seam.
    @Test(arguments: [CameraPreset.front, .back, .left, .right, .top, .bottom])
    func axisSnapEnablesOrthographicProjection(_ preset: CameraPreset) async throws {
        let view = try await readyView()
        view.show(preset)
        #expect(view.activeCameraPreset == preset)
        #expect(view.isOrthographic, "axis-aligned views must automatically use orthographic projection")
        #expect(view.options.isOrthographic, "the projection change must reach the renderer")
    }

    @Test func isometricSnapUsesPerspectiveAfterAnAxisSnap() async throws {
        let view = try await readyView()
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
