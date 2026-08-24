import AppKit
import Foundation
import PreviewUI
import Testing
@testable import GLTFInspector

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
}

/// The one-renderer rule applied to *look*, not just to renderer.
///
/// Same renderer is necessary but not sufficient: if the window, Quick Look and the thumbnail
/// disagree about environment or tone mapping, the same file still renders three ways.
@MainActor
struct RendererLookDefaultsTests {
    private let environmentKey = "settings.preview.environmentCatalog"
    private let toneMappingKey = "settings.preview.toneMapping"

    private func withDefaults(
        environment: String?,
        toneMapping: String?,
        _ body: () throws -> Void
    ) rethrows {
        let suite = UserDefaults.standard
        let previousEnvironment = suite.object(forKey: environmentKey)
        let previousToneMapping = suite.object(forKey: toneMappingKey)
        defer {
            suite.set(previousEnvironment, forKey: environmentKey)
            suite.set(previousToneMapping, forKey: toneMappingKey)
        }
        suite.set(environment, forKey: environmentKey)
        suite.set(toneMapping, forKey: toneMappingKey)
        try body()
    }

    @Test
    func fallsBackToTheReviewOrientedDefaults() {
        withDefaults(environment: nil, toneMapping: nil) {
            let look = RendererLookDefaults.current()
            #expect(look.environment == "neutral")
            // Khronos PBR Neutral distorts authored colour least — the right default for a tool
            // whose job is showing what is in the file.
            #expect(look.toneMapping == "Khronos PBR Neutral")
        }
    }

    @Test
    func readsWhatTheAppStored() {
        withDefaults(environment: "field", toneMapping: "ACES Filmic Tone Mapping (Hill)") {
            let look = RendererLookDefaults.current()
            #expect(look.environment == "field")
            #expect(look.toneMapping == "ACES Filmic Tone Mapping (Hill)")
        }
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

        func render() async throws -> Data? {
            let look = RendererLookDefaults.current()
            let host = try WebRendererHost(mode: .still)
            try await host.start(size: 160)
            try await host.setEnvironment(named: look.environment)
            try await host.send { .setToneMapping(id: $0, name: look.toneMapping) }
            _ = try await host.load(model: model)
            let image = try await host.renderStill()
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }

        var neutral: Data?
        var studio: Data?
        withDefaults(environment: "neutral", toneMapping: "Khronos PBR Neutral") {}
        neutral = try await render()

        let suite = UserDefaults.standard
        let previous = suite.object(forKey: environmentKey)
        suite.set("Colorful_Studio", forKey: environmentKey)
        studio = try await render()
        suite.set(previous, forKey: environmentKey)

        #expect(neutral != nil && studio != nil)
        #expect(neutral != studio, "changing the app default did not change the render")
    }
}
