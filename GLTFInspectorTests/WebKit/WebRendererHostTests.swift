import AppKit
import Foundation
import Testing
@testable import GLTFInspector
@testable import RendererWebKit

/// What goes over the bridge. Pure value work — no web view involved.
struct WebRendererBridgeTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    /// Absent rather than null, so the page can use plain `??` / `undefined` checks.
    @Test
    func cameraCommandOmitsWhatItDoesNotSet() throws {
        let fit = try json(CameraCommand.fit)
        #expect(fit["op"] as? String == "fit")
        #expect(fit["distance"] == nil && fit["pose"] == nil)

        let orbit = try json(CameraCommand.orbit(azimuth: 45, elevation: -20))
        #expect(orbit["azimuth"] as? Double == 45)
        #expect(orbit["distance"] == nil)
        #expect(try json(CameraCommand.orbit(azimuth: 0, elevation: 0, distance: 3.5))["distance"] as? Double == 3.5)
    }

    @Test
    func cameraStateDecodesThePageShape() throws {
        let data = Data(#"""
        {"camera":{"azimuth":25,"elevation":-18,"distance":4,"target":[0,1,0],"yfov":0.78,"znear":0.01,"zfar":10},
         "sceneMin":[-1,0,-1],"sceneMax":[1,2,1]}
        """#.utf8)
        let state = try JSONDecoder().decode(RendererCameraState.self, from: data)
        #expect(state.pose.azimuth == 25)
        #expect(state.sceneCenter == [0, 1, 0])
        #expect(state.isMeasurable && state.pose.isFinite)
    }
}

/// Exercises the real page in an off-screen web view.
///
/// Runs in the test host, which is a normal app — it does not prove the sandboxed extension can
/// do the same. That is what the Finder verification covers.
@MainActor
struct WebRendererHostTests {
    /// A blank or single-colour image is the failure that matters here: `toDataURL` returns a
    /// perfectly well-formed PNG of nothing when the drawing buffer was cleared or the
    /// environment probe came out black.
    ///
    /// Note this does **not** catch a merely *dark* render — during the spike a near-black
    /// silhouette passed a colour count. The pixel-diff harness is what covers that.
    private func distinctColors(in image: CGImage, stride step: Int = 4) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        var seen = Set<UInt32>()
        for y in Swift.stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in Swift.stride(from: 0, to: rep.pixelsWide, by: step) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.01 else { continue }
                seen.insert(
                    (UInt32(color.redComponent * 255) << 16)
                        | (UInt32(color.greenComponent * 255) << 8)
                        | UInt32(color.blueComponent * 255)
                )
            }
        }
        return seen.count
    }

    private func write(_ image: CGImage, to name: String) {
        guard let data = NSBitmapImageRep(cgImage: image)
            .representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        try? data.write(to: url)
        print("web renderer proof → \(url.path)")
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func stillModeRendersOffscreen() async throws {
        let model = TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb")
        try #require(FileManager.default.fileExists(atPath: model.path))

        let host = try await WebKitTest.stillHost()
        let info = try await host.load(model: model)
        #expect(info.triangles > 0)
        #expect(info.meshes > 0)

        let image = try await host.renderStill()
        #expect(image.width == 512)
        #expect(image.height == 512)

        let colors = distinctColors(in: image)
        #expect(colors > 100, "expected a lit render, got \(colors) distinct colours")
        write(image, to: "web-renderer-still.png")
    }

    /// The round trip the whole bridge exists for: a command sent from Swift must visibly change
    /// what the renderer draws. Comparing state would prove nothing — this compares pixels.
    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func cameraCommandChangesTheRenderedImage() async throws {
        let model = TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb")
        let host = try await WebKitTest.stillHost(size: 256)
        try await host.load(model: model)

        try await host.camera(.orbit(azimuth: 0, elevation: 0))
        let front = try await host.renderStill()

        try await host.camera(.orbit(azimuth: 120, elevation: 0))
        let turned = try await host.renderStill()

        // "The images differ" is not enough on its own: an orbit bug that aims the camera away
        // from the model also produces a different image — an empty one. That is exactly what
        // happened here first time round. Both frames must still contain a lit model.
        #expect(distinctColors(in: front) > 100, "front view is empty")
        #expect(distinctColors(in: turned) > 100, "turned view is empty — camera lost the model")

        let a = NSBitmapImageRep(cgImage: front)
            .representation(using: .png, properties: [:])
        let b = NSBitmapImageRep(cgImage: turned)
            .representation(using: .png, properties: [:])
        #expect(a != nil && b != nil)
        #expect(a != b, "camera command did not change the render")

        write(front, to: "web-renderer-azimuth-0.png")
        write(turned, to: "web-renderer-azimuth-120.png")
    }

    @Test
    func liveLoadDrawsTheFirstFrameBeforeReturning() async throws {
        let host = try WebKitTest.host(.live)
        try await host.start()
        let info = try await host.load(model: TestFixtures.tiny)
        #expect(info.triangles > 0)
        #expect(info.width >= 1)
        #expect(info.height >= 1)
        // Still mode leaves this 0; live `load` now waits on the first GPU frame.
        #expect(info.firstFrameMs >= 0)
    }

    @Test
    func commandBeforeReadyFailsRatherThanHanging() async throws {
        let host = try WebKitTest.host()
        await #expect(throws: WebRendererError.notReady) {
            try await host.camera(.fit)
        }
    }

    /// A call that reaches the page and throws must come back as `callFailed` carrying the page's
    /// own message — not as a timeout.
    @Test
    func commandThatThrowsInThePageReportsTheReason() async throws {
        let host = try WebKitTest.host(size: 64)
        try await host.start()

        _ = try await host.load(model: TestFixtures.tiny)
        var look = PageLook(WebPreviewCanvas.Look())
        look.environment = PageLook.environmentURL("no-such-file")
        // The scheme handler 404s, so the environment fetch inside `apply` rejects.
        do {
            try await host.apply(look)
            Issue.record("a missing environment did not fail")
        } catch WebRendererError.callFailed(let message) {
            #expect(message.hasPrefix("apply: "), "\(message)")
        }
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func corruptFileFailsLoudly() async throws {
        let host = try await WebKitTest.stillHost(size: 128)
        await #expect(throws: (any Error).self) {
            _ = try await host.load(model: TestFixtures.corrupt)
        }
    }

    /// The thumbnail writes the page's PNG bytes as they are, so they must already say sRGB —
    /// WebKit's encoder adds the chunk; this catches a WebKit that stops doing so.
    @Test
    func stillPNGIsTaggedSRGBAndSized() async throws {
        let host = try WebKitTest.host(size: 64)
        try await host.start()
        try await host.load(model: TestFixtures.tiny)
        let png = try await host.renderStillPNG(size: 96)

        var chunks: [String] = []
        var offset = 8
        while offset + 8 <= png.count {
            let length = png[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            chunks.append(String(decoding: png[offset + 4..<offset + 8], as: UTF8.self))
            offset += 12 + length
        }
        #expect(chunks.first == "IHDR")
        #expect(chunks.contains("sRGB"), "chunks: \(chunks)")
        let width = png[16..<20].reduce(0) { $0 << 8 | Int($1) }
        #expect(width == 96, "renderStillPNG(size:) did not resize the still canvas")
    }

    @Test
    func rendererBundleKeepsItsNestedLayout() throws {
        let root = try #require(
            Bundle(for: WebRendererHost.self).url(forResource: "web-renderer", withExtension: nil)
        )
        for relative in [
            "viewer.html",
            "gltf-viewer.module.js",
            "libs/libktx.js",
            "libs/libktx.wasm",
            "assets/lut_ggx.png",
            // Licence notices and the upstream pin ship with the bundle.
            "LICENSE.md",
            "THIRD_PARTY_NOTICES.txt",
            "VERSION",
        ] {
            let file = root.appendingPathComponent(relative)
            #expect(FileManager.default.fileExists(atPath: file.path), "missing \(relative)")
        }
    }
}
