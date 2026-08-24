import AppKit
import Foundation
import Testing
@testable import GLTFInspector

/// Proves WebGL renders in a `WKWebView` that was never added to a window.
///
/// This runs in the test host, which is a normal app — it does **not** prove the sandboxed
/// thumbnail extension can do the same. That is the point of the Finder verification step.
@MainActor
struct WebStillRendererTests {
    /// A blank or single-colour image is the failure mode that matters: `toDataURL` happily
    /// returns a fully-formed PNG of nothing when the drawing buffer was cleared or the
    /// environment probe came out black. Counting distinct colours is what catches it.
    private func distinctColors(in image: CGImage, stride step: Int = 4) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        var seen = Set<UInt32>()
        for y in Swift.stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in Swift.stride(from: 0, to: rep.pixelsWide, by: step) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.01 else { continue }
                let packed = (UInt32(color.redComponent * 255) << 16)
                    | (UInt32(color.greenComponent * 255) << 8)
                    | UInt32(color.blueComponent * 255)
                seen.insert(packed)
            }
        }
        return seen.count
    }

    @Test(.enabled(if: TestModels.hasKhronosSamples))
    func rendersBoomBoxOffscreen() async throws {
        let model = TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb")
        try #require(FileManager.default.fileExists(atPath: model.path))

        let result = try await WebStillRenderer(model: model, pixelSize: 512).capture()

        #expect(result.image.width == 512)
        #expect(result.image.height == 512)
        #expect(result.triangles > 0)

        let colors = distinctColors(in: result.image)
        #expect(colors > 100, "expected a lit render, got \(colors) distinct colours")

        // Keep the artifact around — a passing count still deserves eyes on the first run.
        if let data = NSBitmapImageRep(cgImage: result.image).representation(using: .png, properties: [:]) {
            let out = URL(fileURLWithPath: "/tmp/web-still-boombox.png")
            try? data.write(to: out)
            print("web still proof → \(out.path) (\(result.pageMilliseconds) ms in page)")
        }
    }

    @Test
    func failsLoudlyOnCorruptFile() async throws {
        let renderer = WebStillRenderer(
            model: TestFixtures.corrupt,
            pixelSize: 256,
            timeout: .seconds(15)
        )

        await #expect(throws: (any Error).self) {
            _ = try await renderer.capture()
        }
    }

    /// Guards the wiring most likely to break silently: if the renderer folder is flattened
    /// by a resource copy, the relative addon imports fail and the page never reports back.
    @Test
    func rendererBundleKeepsNestedLayout() throws {
        let root = try #require(
            Bundle(for: WebStillRenderer.self).url(forResource: "web-renderer", withExtension: nil)
        )
        for relative in [
            "thumb.html",
            "three.module.min.js",
            "three.core.min.js",
            "addons/loaders/GLTFLoader.js",
            "addons/utils/BufferGeometryUtils.js",
            "addons/environments/RoomEnvironment.js",
        ] {
            let file = root.appendingPathComponent(relative)
            #expect(FileManager.default.fileExists(atPath: file.path), "missing \(relative)")
        }
    }
}
