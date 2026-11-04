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

    /// Moving the window must not move the camera. A title-band drag over the full-bleed canvas
    /// moves the window *with* the pointer: screen deltas are large, window-space motion is zero.
    @Test
    func windowDragDoesNotOrbit() async throws {
        let host = FilamentRendererHost(mode: .live)
        let view = try #require(host.view as? FilamentMetalView)
        let start = try await host.camera(.get).pose.azimuth

        // A drag the view never saw start (the window took the mouse-down) does not orbit.
        view.mouseDragged(with: try drag(at: CGPoint(x: 100, y: 100), screenDeltaX: 40))
        #expect(try await host.camera(.get).pose.azimuth == start)

        // The pointer stays put in the window while the window travels under it.
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: try drag(at: CGPoint(x: 100, y: 100), screenDeltaX: 40))
        #expect(try await host.camera(.get).pose.azimuth == start)

        // A real in-window drag still orbits.
        view.mouseDragged(with: try drag(at: CGPoint(x: 130, y: 100), screenDeltaX: 30))
        #expect(try await host.camera(.get).pose.azimuth != start)
        view.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 130, y: 100)))
    }

    private func mouse(_ type: CGEventType, at point: CGPoint) throws -> NSEvent {
        let event = try #require(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left))
        return try #require(NSEvent(cgEvent: event))
    }

    private func drag(at point: CGPoint, screenDeltaX: Int64) throws -> NSEvent {
        let event = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left))
        event.setIntegerValueField(.mouseEventDeltaX, value: screenDeltaX)
        return try #require(NSEvent(cgEvent: event))
    }
}
