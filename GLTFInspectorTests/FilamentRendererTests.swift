import AppKit
import Foundation
import GLTFCore
import Testing
@testable import GLTFInspector
@testable import RendererWebKit

/// The Filament host behind the same seam the extensions and the window use: a lit still, a
/// framed camera, a rejected file, and a live canvas that reaches `.ready`.
@MainActor
struct FilamentRendererTests {
    /// Alpha of the centre pixel: the model covers it once framed, the clear look leaves the rest.
    private func centreAlpha(_ image: CGImage) throws -> UInt8 {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        return try #require(context.data?.assumingMemoryBound(to: UInt8.self))[3]
    }

    @Test(arguments: [TestFixtures.tiny, TestFixtures.cube, TestFixtures.boxAnimated])
    func stillDrawsTheFramedModel(url: URL) async throws {
        let host = FilamentRendererHost(mode: .still, size: 128)
        try await host.apply(.stored())
        let info = try await host.load(model: url)
        #expect(info.meshes > 0)
        let state = try await host.camera(.get)
        #expect(state.isMeasurable && state.pose.isFinite)

        let png = try await host.renderStillPNG(size: 128)
        let image = try #require(NSBitmapImageRep(data: png)?.cgImage)
        #expect(image.width == 128 && image.height == 128)
        #expect(try centreAlpha(image) > 200)
    }

    @Test
    func rejectedFileThrows() async throws {
        let host = FilamentRendererHost(mode: .still, size: 64)
        try await host.apply(.stored())
        await #expect(throws: WebRendererError.self) {
            try await host.load(model: TestFixtures.fixture("corrupt/truncated.glb"))
        }
    }

    @Test
    func liveCanvasReachesReady() async throws {
        let canvas = WebCanvasController()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        canvas.attach(
            to: container, url: TestFixtures.cube, look: WebPreviewCanvas.Look(), placeholder: nil,
            existing: FilamentRendererHost(mode: .live)
        )
        _ = try await WebKitTest.waitUntil { canvas.phase != .loading }
        #expect(canvas.phase == .ready)
        try await canvas.apply(preset: .isometric)
        let frame = try await canvas.snapshot()
        #expect(frame.width > 1)
    }
}
