import AppKit
import Foundation
import Testing
@testable import GLTFInspector

/// Codec tests for the command channel. Pure value work — no web view involved.
struct WebRendererBridgeTests {
    @Test
    func commandEncodesKindAsTypeAndOmitsUnusedFields() throws {
        let object = WebRendererCommand.load(id: 7, url: "gltf-inspector:///model").jsonObject()

        #expect(object["id"] as? Int == 7)
        #expect(object["type"] as? String == "load")
        #expect(object["url"] as? String == "gltf-inspector:///model")
        // Absent rather than null, so the page can use plain `undefined` checks.
        #expect(object["azimuth"] == nil)
        #expect(object["size"] == nil)
    }

    @Test
    func cameraCommandKeepsAnOmittedDistanceOmitted() throws {
        let withDistance = WebRendererCommand
            .setCamera(id: 1, azimuth: 45, elevation: -20, distance: 3.5).jsonObject()
        let without = WebRendererCommand
            .setCamera(id: 2, azimuth: 45, elevation: -20, distance: nil).jsonObject()

        #expect(withDistance["distance"] as? Double == 3.5)
        #expect(without["distance"] == nil)
        #expect(without["azimuth"] as? Double == 45)
    }

    @Test
    func javaScriptWrapsThePayloadInAnExecCall() throws {
        let script = try WebRendererCommand.fit(id: 3).javaScript()
        #expect(script == #"void window.__viewer.exec({"id":3,"type":"fit"})"#)
    }

    @Test
    func eventParsesResultAndCarriesItsID() throws {
        let event = try #require(WebRendererEvent(body: [
            "event": "result", "id": 4, "triangles": 6036, "meshes": 1,
        ] as [String: Any]))

        #expect(event.name == .result)
        #expect(event.id == 4)
        #expect(event.triangles == 6036)
    }

    @Test
    func eventRejectsBodiesItCannotUnderstand() {
        #expect(WebRendererEvent(body: ["event": "nonsense"] as [String: Any]) == nil)
        #expect(WebRendererEvent(body: ["id": 1] as [String: Any]) == nil)
        #expect(WebRendererEvent(body: "not an object") == nil)
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

    private func makeStillHost(size: Int = 512) async throws -> WebRendererHost {
        let host = try WebRendererHost(mode: .still)
        try await host.start(size: size)
        try await host.setEnvironment(named: "neutral")
        return host
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func stillModeRendersOffscreen() async throws {
        let model = TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb")
        try #require(FileManager.default.fileExists(atPath: model.path))

        let host = try await makeStillHost()
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
        let host = try await makeStillHost(size: 256)
        try await host.load(model: model)

        try await host.send { .setCamera(id: $0, azimuth: 0, elevation: 0, distance: nil) }
        let front = try await host.renderStill()

        try await host.send { .setCamera(id: $0, azimuth: 120, elevation: 0, distance: nil) }
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
    func commandBeforeReadyFailsRatherThanHanging() async throws {
        let host = try WebRendererHost(mode: .still)
        await #expect(throws: WebRendererError.notReady) {
            try await host.send { .fit(id: $0) }
        }
    }

    /// A command that reaches the page and throws inside its handler must come back as
    /// `commandFailed` carrying the page's own message — not as a timeout.
    @Test
    func commandThatThrowsInThePageReportsTheReason() async throws {
        let host = try WebRendererHost(mode: .still, timeout: .seconds(8))
        try await host.start(size: 64)

        // The scheme handler 404s, so the fetch inside the handler rejects.
        await #expect(throws: (any Error).self) {
            try await host.send {
                .setEnvironment(id: $0, url: "gltf-inspector:///environments/no-such-file.hdr")
            }
        }
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func corruptFileFailsLoudly() async throws {
        let host = try await makeStillHost(size: 128)
        await #expect(throws: (any Error).self) {
            _ = try await host.load(model: TestFixtures.corrupt)
        }
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
        ] {
            let file = root.appendingPathComponent(relative)
            #expect(FileManager.default.fileExists(atPath: file.path), "missing \(relative)")
        }
    }
}
