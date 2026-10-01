import AppKit
import Foundation
@testable import GLTFCore
import PreviewUI
import Testing
@testable import GLTFInspector
@testable import RendererWebKit

/// Every viewport control, asserted against **rendered pixels**.
///
/// Controller state proves nothing here. Several bugs in this migration passed state-level
/// checks while the picture was blank or unchanged: a camera command that aimed away from the
/// model, and a canvas that rendered 1x1 while reporting a successful load. So each test renders
/// a frame, checks the frame still contains a model, and checks it actually changed.
@MainActor
struct WebRendererControlsTests {
    private func makeHost() async throws -> WebRendererHost {
        let host = try await WebKitTest.stillHost(size: 192)
        _ = try await host.load(
            model: TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb")
        )
        return host
    }

    private func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Guards against "it changed" being satisfied by an empty frame.
    private func opaqueSamples(in image: CGImage) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        var count = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.01 { count += 1 }
            }
        }
        return count
    }

    /// Renders before and after, and requires both a real change and a model still on screen.
    private func expectVisibleChange(
        _ host: WebRendererHost,
        applying change: (inout WebPreviewCanvas.Look) -> Void,
        _ label: String
    ) async throws {
        let before = try await host.renderStill()
        var look = WebPreviewCanvas.Look()
        change(&look)
        try await host.apply(look)
        let after = try await host.renderStill()

        #expect(opaqueSamples(in: before) > 50, "\(label): baseline frame is empty")
        #expect(opaqueSamples(in: after) > 50, "\(label): frame is empty after the change")
        #expect(png(before) != png(after), "\(label) did not change the render")
    }

    /// The backdrop is the page background behind a transparent canvas, so it does not appear
    /// in `toDataURL` output at all — the drawing buffer is genuinely transparent where the
    /// model is not. Asserting on rendered pixels would fail for the right reason, so this
    /// checks the page instead.
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func backdropPaintsThePageBackground() async throws {
        let host = try await makeHost()
        var look = WebPreviewCanvas.Look()
        look.render.background = RenderLook.Color(red: 1, green: 1, blue: 1, alpha: 1)
        try await host.apply(look)

        // The browser normalises a fully opaque rgba() to rgb(), so match on the components.
        let background = try await host.stats().background
        #expect(background.contains("255, 255, 255"), "backdrop did not paint the page: \(background)")

        try await host.apply(WebPreviewCanvas.Look())
        let cleared = try await host.stats().background
        #expect(
            cleared.contains("0, 0, 0, 0") || cleared == "transparent",
            "transparent backdrop did not clear the page: \(cleared)"
        )

        // The model must still be there — a backdrop change must not disturb the render.
        let image = try await host.renderStill()
        #expect(opaqueSamples(in: image) > 50, "model vanished after the backdrop change")
        assertTransparentCorners(image)
    }

    /// Environment-as-skybox or Khronos's opaque clear would fill every corner.
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func stillFrameCornersAreTransparent() async throws {
        let host = try await makeHost()
        assertTransparentCorners(try await host.renderStill())
    }

    private func assertTransparentCorners(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let maxX = max(0, rep.pixelsWide - 1)
        let maxY = max(0, rep.pixelsHigh - 1)
        for (x, y) in [(0, 0), (maxX, 0), (0, maxY), (maxX, maxY)] {
            let alpha = rep.colorAt(x: x, y: y)?.alphaComponent ?? 1
            #expect(alpha < 0.01, "canvas corner (\(x),\(y)) is opaque: alpha=\(alpha)")
        }
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func projectionChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { $0.isOrthographic = true }, "projection"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func fieldOfViewChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { $0.fieldOfView = 20 }, "field of view"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func toneMappingChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host,
            applying: { $0.render.toneMapping = .acesHill },
            "tone mapping"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func exposureChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { $0.render.exposureEV = 2 }, "exposure"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func environmentRotationChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { $0.render.environmentYawDegrees = 90 }, "environment rotation"
        )
    }

    /// The channel names are matched by string inside the renderer, so a typo silently renders
    /// normally rather than failing. Comparing pixels is the only way to know they landed.
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func everyDebugChannelChangesTheRender() async throws {
        let host = try await makeHost()
        let shaded = try await host.renderStill()

        for channel: RenderViewMode.Channel in [.baseColor, .metallic, .roughness, .normals, .emissive,
                                                .ambientOcclusion, .alpha, .textureCoordinates, .tangents] {
            try await host.apply(WebPreviewCanvas.Look(viewMode: .channel(channel)))
            let debug = try await host.renderStill()
            #expect(opaqueSamples(in: debug) > 50, "\(channel): frame is empty")
            #expect(png(shaded) != png(debug), "debug channel '\(channel)' did not change the render")
        }

        try await host.apply(WebPreviewCanvas.Look())
        let restored = try await host.renderStill()
        #expect(png(restored) == png(shaded), "leaving debug mode did not restore shaded output")
    }

    /// `setEnvironment` re-samples the IBL probe, which is the expensive path and the one most
    /// likely to silently no-op.
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func switchingEnvironmentChangesTheLighting() async throws {
        let host = try await makeHost()
        let neutral = try await host.renderStill()

        var look = WebPreviewCanvas.Look()
        look.render.environment = .colorfulStudio
        try await host.apply(look)
        let studio = try await host.renderStill()

        #expect(opaqueSamples(in: studio) > 50, "studio frame is empty")
        #expect(png(neutral) != png(studio), "environment switch did not change the lighting")
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func floorChangesPixelsWithoutMovingTheCamera() async throws {
        let host = try await makeHost()
        let before = try await host.cameraState()
        try await expectVisibleChange(
            host, applying: { $0.showsFloor = true }, "floor"
        )
        let after = try await host.cameraState()
        #expect(before.pose.distance == after.pose.distance, "floor moved the camera distance")
        #expect(before.pose.target == after.pose.target, "floor moved the camera target")
        #expect(before.pose.azimuth == after.pose.azimuth, "floor moved the camera azimuth")
        #expect(before.pose.elevation == after.pose.elevation, "floor moved the camera elevation")
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func authoredOriginGizmoChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { $0.isCentered = false }, "authored origin"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func wireframeChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { $0.viewMode = .wireframe }, "wireframe"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func selectingANodeHighlightsTheCanvas() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { $0.selectedNodeIndex = 0 }, "selection"
        )
    }
}

/// The one-renderer rule applied to *look*, not just to renderer: Quick Look and the thumbnail
/// render with the look Settings stored (`WebPreviewCanvas.Look.stored`). The reader itself is
/// covered by `AppGroupSettingsTests`.
@MainActor
struct StoredLookRenderTests {
    /// A throwaway suite + look directory standing in for the App Group.
    private struct Store {
        let defaults: UserDefaults
        let directory: URL
        let suiteName: String

        init() throws {
            suiteName = "gltf.renderer-look.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(suiteName, isDirectory: true)
        }

        func setEnvironment(_ raw: String) {
            var look = AppLook.default
            look.catalogRaw = raw
            look.save(to: directory)
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Renders the same file twice with different stored defaults and requires the pixels to
    /// differ — proof the setting reaches the renderer, not just that it was stored.
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func changingTheDefaultChangesWhatTheThumbnailPathRenders() async throws {
        let model = TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb")
        let store = try Store()
        defer { store.tearDown() }

        func render() async throws -> Data? {
            let host = try WebKitTest.host(size: 160)
            try await host.start()
            try await host.apply(.stored(defaults: store.defaults, directory: store.directory))
            _ = try await host.load(model: model)
            let image = try await host.renderStill()
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }

        store.setEnvironment("neutral")
        let neutral = try await render()
        store.setEnvironment("Colorful_Studio")
        let studio = try await render()

        #expect(neutral != nil && studio != nil)
        #expect(neutral != studio, "changing the app default did not change the render")
    }
}

/// Thumbnail path: still host + app look, including `.gltf` sidecars.
@MainActor
struct WebRendererThumbnailPathTests {
    @Test
    func sidecarGLTFProducesAStill() async throws {
        let host = try await WebKitTest.stillHost(size: 128)
        _ = try await host.load(model: TestFixtures.cube)
        let image = try await host.renderStill()
        #expect(image.width > 8)
        #expect(image.height > 8)
    }

    @Test
    func corruptFileFailsInsteadOfHanging() async throws {
        let host = try WebKitTest.host(size: 64)
        try await host.start()
        await #expect(throws: Error.self) {
            _ = try await host.load(model: TestFixtures.corrupt)
        }
    }
}
