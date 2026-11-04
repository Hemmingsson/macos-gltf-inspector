import AppKit
import Foundation
import GLTFCore
import simd
import Testing
@testable import Renderer

/// Polls `condition` until it holds or `limit` passes. Wait on state, never on a fixed sleep.
@MainActor
func waitUntil(within limit: Duration = .seconds(30), _ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + limit
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// Alpha of the centre pixel of `image`.
@MainActor
func centreAlpha(_ image: CGImage) throws -> UInt8 {
    let context = try #require(CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let point = CGPoint(x: image.width / 2, y: image.height / 2)
    context.draw(image, in: CGRect(x: -point.x, y: -point.y, width: CGFloat(image.width), height: CGFloat(image.height)))
    return try #require(context.data?.assumingMemoryBound(to: UInt8.self))[3]
}

/// The window's and Quick Look's canvas: the load phase, camera commands, and a view that
/// survives a SwiftUI remount.
@MainActor
@Suite(.serialized)
struct ModelCanvasControllerTests {
    private func mount(_ canvas: ModelCanvasController, url: URL, options: ViewOptions = ViewOptions()) -> NSView {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        canvas.mount(in: container, url: url, options: options)
        return container
    }

    private func settled(_ canvas: ModelCanvasController) async throws -> ModelCanvasController.Phase {
        _ = try await waitUntil { canvas.phase != .loading }
        return canvas.phase
    }

    @Test func corruptFileEndsInFailedAndStaysThere() async throws {
        let canvas = ModelCanvasController()
        _ = mount(canvas, url: TestFixtures.corrupt)
        #expect(try await settled(canvas) == .failed(ModelCanvasController.message(for: MetalSceneError.invalid(""))))
        #expect(throws: (any Error).self) { try canvas.snapshot() }
        // The failure re-renders the owner, which updates again: that must not retry.
        canvas.update(url: TestFixtures.corrupt, options: ViewOptions(showsFloor: true))
        #expect(try await !waitUntil(within: .milliseconds(300)) { canvas.phase == .loading })
    }

    @Test func aFailedCanvasLoadsTheNextFile() async throws {
        let canvas = ModelCanvasController()
        _ = mount(canvas, url: TestFixtures.corrupt)
        guard case .failed = try await settled(canvas) else { Issue.record("expected .failed"); return }
        canvas.update(url: TestFixtures.cube, options: ViewOptions())
        #expect(try await waitUntil { canvas.phase == .ready })
    }

    /// Quick Look's path: the stored look with a floor, a preset, and an export at the canvas
    /// size rather than a square.
    @Test func readyCanvasTakesPresetsAndExportsAtCanvasSize() async throws {
        let canvas = ModelCanvasController()
        _ = mount(canvas, url: TestFixtures.cube, options: .stored(showsFloor: true))
        #expect(try await settled(canvas) == .ready)

        canvas.show(.top)
        let top = try canvas.snapshot()
        canvas.show(.right)
        let right = try canvas.snapshot()
        #expect(top.width * 240 == top.height * 320)
        #expect(try centreAlpha(right) > 200)
        #expect(top.dataProvider?.data != right.dataProvider?.data, "the preset did not move the camera")
    }

    /// The document window remounts its canvas for a new document. The owner-held controller
    /// moves its running view into the new container instead of starting another renderer.
    @Test func remountAdoptsTheRunningView() async throws {
        let canvas = ModelCanvasController()
        _ = mount(canvas, url: TestFixtures.cube)
        #expect(try await settled(canvas) == .ready)
        let view = try #require(canvas.view)

        let second = mount(canvas, url: TestFixtures.cube)
        #expect(view.superview === second)
        #expect(canvas.phase == .ready)
        #expect(try canvas.snapshot().width > 1)
    }

    /// Options that change while the file loads (the panels land mid-load and pick the scene)
    /// must not strand the canvas in `.loading`, and the latest options win.
    @Test func optionsChangedDuringLoadStillReachReadyWithTheLatestOptions() async throws {
        let canvas = ModelCanvasController()
        _ = mount(canvas, url: TestFixtures.lights)
        #expect(canvas.phase == .loading)
        var options = ViewOptions()
        options.look.exposureEV = 1
        canvas.update(url: TestFixtures.lights, options: options)
        options.showsFloor = true
        canvas.update(url: TestFixtures.lights, options: options)

        #expect(try await settled(canvas) == .ready)
        #expect(try await waitUntil { canvas.view?.options == options })
    }

    /// A new document in the same window loads with its own options, scene included.
    @Test func aSecondFileLoadsWithItsOwnScene() async throws {
        let canvas = ModelCanvasController()
        _ = mount(canvas, url: TestFixtures.cube)
        #expect(try await settled(canvas) == .ready)
        canvas.update(url: TestFixtures.multiScene, options: ViewOptions(sceneIndex: 1))
        #expect(try await waitUntil { canvas.phase == .ready && canvas.view?.options.sceneIndex == 1 })
        #expect(try canvas.snapshot().width > 1)
    }

    @Test func zoomPercentFollowsCameraCommands() async throws {
        let canvas = ModelCanvasController()
        _ = mount(canvas, url: TestFixtures.cube)
        #expect(try await settled(canvas) == .ready)
        #expect(canvas.zoomPercent == 100)
        canvas.zoom(by: 2)
        #expect(canvas.zoomPercent == 50)
        canvas.fit()
        #expect(canvas.zoomPercent == 100)
    }
}

@MainActor
@Suite(.serialized)
struct ModelViewTests {
    private func loaded(_ url: URL, options: ViewOptions = ViewOptions()) async throws -> ModelView {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.apply(options)
        try await view.load(url)
        return view
    }

    @Test func aRejectedFileKeepsThePreviousModel() async throws {
        let view = try await loaded(TestFixtures.cube)
        await #expect(throws: (any Error).self) { try await view.load(TestFixtures.corrupt) }
        #expect(try view.image(width: 64, height: 64).width == 64)
    }

    /// A variant change redraws but does not refit; a scene change refits.
    @Test func optionChangesRefitOnlyForSceneAndCentring() async throws {
        let view = try await loaded(TestFixtures.multiScene)
        view.orbit(azimuth: 50, elevation: 10)
        let before = view.camera
        var options = view.options
        options.showsFloor = true
        options.materialVariantIndex = nil
        try await view.apply(options)
        #expect(view.camera == before, "an option change without refit moved the camera")
        options.sceneIndex = 1
        try await view.apply(options)
        #expect(view.camera != before)
    }

    /// `UserCamera.zoomBy`, `orbit` and `pan` against values worked from the Khronos source.
    @Test func unmodifiedClickAtCentrePicksMesh() async throws {
        let view = try await loaded(TestFixtures.cube)
        view.frame = NSRect(x: 0, y: 0, width: 512, height: 512)
        view.layoutSubtreeIfNeeded()
        // Off-screen fixture window: pick needs a window, but must not steal focus (AGENTS.md).
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }

        var picked: Int?
        view.onPick = { picked = $0 }

        let centre = NSPoint(x: 256, y: 256)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: centre, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        view.mouseDown(with: event(.leftMouseDown))
        view.mouseUp(with: event(.leftMouseUp))
        #expect(picked == 0)
    }

    @Test func userCameraInputFollowsKhronos() {
        var camera = MetalUserCamera()
        camera.fit(extents: (SIMD3(-1, -1, -1), SIMD3(1, 1, 1)), centered: true, aspect: 1)
        let base = camera.baseDistance
        camera.zoomBy(10)
        #expect(abs(camera.distance - pow(1 + 0.1, 5) * base) < 1e-9)
        let diagonal = simd_distance(SIMD3<Double>(-1, -1, -1), SIMD3<Double>(1, 1, 1))
        #expect(abs(camera.zfar - (camera.distance + 6 * diagonal)) < 1e-9, "wheel zoom refits the far plane")
        camera.orbit(90, 0)
        #expect(abs(camera.rotAroundY + 0.5) < 1e-12, "90 px orbit is -0.5 rad")
        camera.orbit(0, 10_000)
        #expect(abs(camera.rotAroundX + (Double.pi / 2 - 0.01)) < 1e-12, "elevation clamps at π/2 - 0.01")
        let target = camera.target
        camera.pan(-35, 0)
        #expect(abs(simd_distance(camera.target, target) - 35 * diagonal / 3500 * camera.distance / base) < 1e-9)
    }

    @Test func orthographicLetterboxIsSquare() {
        let wide = khronosViewport(width: 1000, height: 500, aspect: 1)
        #expect(wide.originX == 250 && wide.originY == 0 && wide.width == 500 && wide.height == 500)
        let tall = khronosViewport(width: 300, height: 601, aspect: 1)
        #expect(tall.originX == 0 && tall.width == 300 && tall.height == 300 && tall.originY == 151)
        let full = khronosViewport(width: 640, height: 480, aspect: nil)
        #expect(full.originX == 0 && full.originY == 0 && full.width == 640 && full.height == 480)
    }
}

/// The Finder thumbnail's render path in-process: the exact type `ThumbnailProvider` calls.
@MainActor
@Suite(.serialized)
struct ThumbnailRendererTests {
    @Test func rendersAFramedSquareThumbnail() async throws {
        let image = try await ThumbnailRenderer().render(url: TestFixtures.cube, pixel: 256)
        #expect(image.width == 256 && image.height == 256)
        #expect(try centreAlpha(image) > 200, "the framed model covers the centre")
    }

    /// Finder asks for a folder at once: requests run one at a time on one view, a rejected file
    /// fails alone, and the next file still renders. Draco goes through DracoSwift.
    @Test func serializesRequestsAndSurvivesARejectedFile() async throws {
        let manifest = try PixelDiffManifest.load()
        let draco = try #require(manifest.entries.first { $0.name == "BoxDraco" }).modelURL
        let renderer = ThumbnailRenderer()

        async let first = renderer.render(url: TestFixtures.boxAnimated, pixel: 128)
        async let second = renderer.render(url: draco, pixel: 128)
        for image in try await [first, second] {
            #expect(image.width == 128)
            #expect(try centreAlpha(image) > 200)
        }
        await #expect(throws: (any Error).self) { try await renderer.render(url: TestFixtures.corrupt, pixel: 128) }
        #expect(try await renderer.render(url: TestFixtures.tiny, pixel: 128).width == 128)
    }
}
