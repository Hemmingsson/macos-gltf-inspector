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
        let host = try WebRendererHost(mode: .still)
        try await host.start(size: 192)
        try await host.setEnvironment(named: "neutral")
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
        applying command: @escaping (Int) -> WebRendererCommand,
        _ label: String
    ) async throws {
        let before = try await host.renderStill()
        try await host.send(command)
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
        try await host.send { .setBackdrop(id: $0, color: [1, 1, 1, 1]) }

        // The browser normalises a fully opaque rgba() to rgb(), so match on the components.
        let background = try await host.evaluate(
            "getComputedStyle(document.body).backgroundColor"
        )
        #expect(background.contains("255, 255, 255"), "backdrop did not paint the page: \(background)")

        try await host.send { .setBackdrop(id: $0, color: [0, 0, 0, 0]) }
        let cleared = try await host.evaluate("getComputedStyle(document.body).backgroundColor")
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
            host, applying: { .setProjection(id: $0, name: "orthographic") }, "projection"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func fieldOfViewChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { .setFieldOfView(id: $0, degrees: 20) }, "field of view"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func toneMappingChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host,
            applying: { .setToneMapping(id: $0, name: "ACES Filmic Tone Mapping (Hill)") },
            "tone mapping"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func exposureChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { .setExposure(id: $0, stops: 2) }, "exposure"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func environmentRotationChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { .setEnvironmentRotation(id: $0, degrees: 180) }, "environment rotation"
        )
    }

    /// The channel names are matched by string inside the renderer, so a typo silently renders
    /// normally rather than failing. Comparing pixels is the only way to know they landed.
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func everyDebugChannelChangesTheRender() async throws {
        let host = try await makeHost()
        let shaded = try await host.renderStill()

        for channel in ["Base Color", "Metallic", "Roughness", "Normal Texture", "Emissive",
                        "Occlusion", "Alpha", "Texture Coordinates 0", "Geometry Tangent"] {
            try await host.send { .setDebugChannel(id: $0, name: channel) }
            let debug = try await host.renderStill()
            #expect(opaqueSamples(in: debug) > 50, "\(channel): frame is empty")
            #expect(png(shaded) != png(debug), "debug channel '\(channel)' did not change the render")
        }

        try await host.send { .setDebugChannel(id: $0, name: "None") }
        let restored = try await host.renderStill()
        #expect(png(restored) == png(shaded), "leaving debug mode did not restore shaded output")
    }

    /// `setEnvironment` re-samples the IBL probe, which is the expensive path and the one most
    /// likely to silently no-op.
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func switchingEnvironmentChangesTheLighting() async throws {
        let host = try await makeHost()
        let neutral = try await host.renderStill()

        try await host.setEnvironment(named: "Colorful_Studio")
        let studio = try await host.renderStill()

        #expect(opaqueSamples(in: studio) > 50, "studio frame is empty")
        #expect(png(neutral) != png(studio), "environment switch did not change the lighting")
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func floorChangesPixelsWithoutMovingTheCamera() async throws {
        let host = try await makeHost()
        let before = try await host.cameraState()
        try await expectVisibleChange(
            host, applying: { .setFloor(id: $0, enabled: true) }, "floor"
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
            host, applying: { .setCenter(id: $0, enabled: false) }, "authored origin"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func wireframeChangesTheRender() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { .setWireframe(id: $0, enabled: true) }, "wireframe"
        )
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func selectingANodeHighlightsTheCanvas() async throws {
        let host = try await makeHost()
        try await expectVisibleChange(
            host, applying: { .setSelectedNode(id: $0, index: 0) }, "selection"
        )
    }
}

/// The one-renderer rule applied to *look*, not just to renderer.
///
/// Same renderer is necessary but not sufficient: if the window, Quick Look and the thumbnail
/// disagree about environment or tone mapping, the same file still renders three ways.
@MainActor
struct RendererLookDefaultsTests {
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

        func look() -> (environment: String, toneMapping: String) {
            AppGroupSettings.rendererLook(defaults: defaults, directory: directory)
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test
    func fallsBackToTheReviewOrientedDefaults() throws {
        let store = try Store()
        defer { store.tearDown() }
        let look = store.look()
        #expect(look.environment == "neutral")
        // Khronos PBR Neutral distorts authored colour least — the right default for a tool
        // whose job is showing what is in the file.
        #expect(look.toneMapping == "Khronos PBR Neutral")
    }

    @Test
    func readsWhatTheAppStored() throws {
        let store = try Store()
        defer { store.tearDown() }
        store.setEnvironment("field")
        store.defaults.set("ACES Filmic Tone Mapping (Hill)", forKey: AppGroupSettings.Key.toneMapping)
        let look = store.look()
        #expect(look.environment == "field")
        #expect(look.toneMapping == "ACES Filmic Tone Mapping (Hill)")
    }

    /// The stored string is what reaches the renderer, so a mismatch between the enum and the
    /// persisted name silently renders with the wrong curve.
    @Test
    func everyToneMappingRoundTripsThroughItsStoredName() {
        for option in ToneMapping.allCases {
            #expect(ToneMapping.fromKhronosName(option.khronosName) == option)
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
            let look = store.look()
            let host = try WebRendererHost(mode: .still)
            try await host.start(size: 160)
            try await host.setEnvironment(named: look.environment)
            try await host.send { .setToneMapping(id: $0, name: look.toneMapping) }
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
        let host = try WebRendererHost(mode: .still)
        try await host.start(size: 128)
        try await host.setEnvironment(named: "neutral")
        _ = try await host.load(model: TestFixtures.cube)
        let image = try await host.renderStill()
        #expect(image.width > 8)
        #expect(image.height > 8)
    }

    @Test
    func corruptFileFailsInsteadOfHanging() async throws {
        let host = try WebRendererHost(mode: .still)
        try await host.start(size: 64)
        await #expect(throws: Error.self) {
            _ = try await host.load(model: TestFixtures.corrupt)
        }
    }

    /// Cold still of BoomBox — the spike's 1807 ms comparison point.
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func recordsSingleFileStillTiming() async throws {
        let started = CFAbsoluteTimeGetCurrent()
        let host = try WebRendererHost(mode: .still)
        try await host.start(size: 256)
        try await host.setEnvironment(named: "neutral")
        _ = try await host.load(model: TestModels.boomBox)
        let image = try await host.renderStill()
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        print(String(format: "thumb-bench single BoomBox %.0fms %dx%d", ms, image.width, image.height))
        #expect(image.width == 256)
        #expect(ms < 15_000)
    }

    /// 100 sequential stills on one warm host (the reuse lever) plus 12 cold hosts.
    @Test
    func recordsFolderScaleStillTiming() async throws {
        let files = [TestFixtures.tiny] + TestModels.khronosGLBs.prefix(11)
        let warmHost = try WebRendererHost(mode: .still)
        try await warmHost.start(size: 64)
        try await warmHost.setEnvironment(named: "neutral")
        let warmStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<100 {
            _ = try await warmHost.load(model: files[i % files.count])
            _ = try await warmHost.renderStill()
        }
        let warmMs = (CFAbsoluteTimeGetCurrent() - warmStart) * 1000
        print(String(format: "thumb-bench warm 100 stills %.0fms (%.0fms/file)", warmMs, warmMs / 100))

        let coldCount = min(12, max(1, files.count))
        let coldStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<coldCount {
            let host = try WebRendererHost(mode: .still)
            try await host.start(size: 64)
            try await host.setEnvironment(named: "neutral")
            _ = try await host.load(model: files[i % files.count])
            _ = try await host.renderStill()
        }
        let coldMs = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000
        print(String(
            format: "thumb-bench cold %d hosts %.0fms (%.0fms/file)",
            coldCount, coldMs, coldMs / Double(coldCount)
        ))
        #expect(warmMs / 100 < 5_000)
    }
}
