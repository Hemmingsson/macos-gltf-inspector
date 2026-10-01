import AppKit
import Foundation
import GLTFCore
import Testing
@testable import GLTFInspector
@testable import RendererWebKit

/// The web canvas's half of the canvas seam: load phase (ending in `.failed`), camera commands
/// through the page, and a page that survives a remount of `WebPreviewCanvas`.
@MainActor
struct WebCanvasControllerTests {
    /// Waits for the controller to leave `.loading`. The cap only keeps a regression from hanging
    /// the suite.
    private func settledPhase(
        of canvas: WebCanvasController,
        within limit: Duration = WebKitTest.timeout
    ) async throws -> WebCanvasController.Phase {
        _ = try await WebKitTest.waitUntil(within: limit) { canvas.phase != .loading }
        return canvas.phase
    }

    /// Mounts on a test-budget live host (`existing:`), so a loaded machine cannot time out the page.
    /// A remount of an attached controller reuses its running host and ignores `existing:`.
    private func mount(_ canvas: WebCanvasController, url: URL) throws -> NSView {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let fresh = try canvas.host == nil ? WebKitTest.host(.live) : nil
        canvas.attach(
            to: container, url: url, look: WebPreviewCanvas.Look(), placeholder: nil, existing: fresh
        )
        return container
    }

    @Test
    func corruptFileEndsInFailedNotASpinner() async throws {
        let canvas = WebCanvasController()
        _ = try mount(canvas, url: TestFixtures.corrupt)

        let phase = try await settledPhase(of: canvas)
        guard case .failed(let message) = phase else {
            Issue.record("expected .failed, got \(phase)")
            return
        }
        #expect(!message.isEmpty)
        // Commands refuse a canvas that never drew.
        await #expect(throws: WebRendererError.notReady) {
            try await canvas.fit()
        }
    }

    @Test
    func loadedCanvasTakesCameraCommandsAndSnapshots() async throws {
        let canvas = WebCanvasController()
        _ = try mount(canvas, url: TestFixtures.cube)
        #expect(try await settledPhase(of: canvas) == .ready)

        try await canvas.fit()
        try await canvas.apply(preset: .top)
        let top = try await canvas.snapshot()
        try await canvas.apply(preset: .right)
        let right = try await canvas.snapshot()

        #expect(top.width > 1 && top.height > 1)
        #expect(right.width == top.width)
        // The preset reached the page: two views of the lit cube are different frames.
        #expect(top.dataProvider?.data != right.dataProvider?.data, "preset did not move the camera")
    }

    /// The document window remounts its shell when convert lands. An owner-held controller must
    /// move the running page into the new view rather than start another one.
    @Test
    func remountAdoptsTheRunningPage() async throws {
        let canvas = WebCanvasController()
        let first = try mount(canvas, url: TestFixtures.cube)
        #expect(try await settledPhase(of: canvas) == .ready)
        let webView = try #require(first.subviews.first { $0.className.contains("WKWebView") })

        WebPreviewCanvas.dismantleNSView(first, coordinator: canvas)
        let second = try mount(canvas, url: TestFixtures.cube)

        #expect(webView.superview === second)
        #expect(canvas.phase == .ready)
        // Same page, still drawing: commands and a frame work without a second load.
        try await canvas.fit()
        let frame = try await canvas.snapshot()
        #expect(frame.width > 1)
    }

    /// A lost WebGL context kills the page. The canvas loads a fresh page and redraws once;
    /// a second loss for the same model ends in `.failed`, not a restart loop.
    @Test
    func lostContextRestartsThePageOnceThenFails() async throws {
        let canvas = WebCanvasController()
        _ = try mount(canvas, url: TestFixtures.cube)
        #expect(try await settledPhase(of: canvas) == .ready)
        let host = try #require(canvas.host)

        // The `contextlost` event arrives asynchronously: wait for the restart to leave `.ready`
        // (a page start is far longer than one poll), then for the redraw.
        try await host.evaluate(Self.loseContext)
        let restarted = try await WebKitTest.waitUntil { canvas.phase != .ready }
        try #require(restarted, "first context loss did not restart the page")
        #expect(try await settledPhase(of: canvas) == .ready)
        let frame = try await canvas.snapshot()
        #expect(frame.width > 1)

        try await host.evaluate(Self.loseContext)
        let failed = try await WebKitTest.waitUntil {
            if case .failed = canvas.phase { true } else { false }
        }
        guard failed, case .failed(let message) = canvas.phase else {
            Issue.record("expected .failed after a second context loss, got \(canvas.phase)")
            return
        }
        #expect(message == WebRendererError.contextLost.errorDescription)
    }

    private static let loseContext =
        "document.getElementById('stage').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext()"

    @Test
    func timedOutHostFailsFastAfterwards() async throws {
        let host = try WebRendererHost(mode: .still, size: 64, timeout: .milliseconds(1))
        await #expect(throws: WebRendererError.timedOut) {
            try await host.start()
        }
        #expect(host.isBroken)
        await #expect(throws: WebRendererError.timedOut) {
            try await host.camera(.fit)
        }
        // A later start loads a fresh page instead of rethrowing the old failure.
        host.timeout = WebKitTest.timeout
        try await host.start()
        #expect(!host.isBroken)
    }

    /// Each call has its own budget: one that never answers times out alone, and the page keeps
    /// serving the next call.
    @Test
    func aHungCallTimesOutWithoutFailingTheNext() async throws {
        let host = try WebKitTest.host(size: 64)
        try await host.start()
        try await host.evaluate(
            "(() => { const camera = window.__viewer.camera; window.__viewer.camera = (c) => c.op === 'fit' ? (window.__hung = new Promise(() => {})) : camera(c); return 1 })()"
        )
        host.timeout = .milliseconds(300)
        await #expect(throws: WebRendererError.timedOut) {
            try await host.camera(.fit)
        }
        host.timeout = WebKitTest.timeout
        try await host.camera(.get)
        #expect(!host.isBroken)
    }
}

/// Pure preset math — no web view.
struct WebCameraPresetTests {
    private func state(min: [Double], max: [Double], distance: Double = 10) -> RendererCameraState {
        RendererCameraState(
            pose: CameraPose(
                azimuth: 0, elevation: 0, distance: distance,
                target: [0, 0, 0], yfov: 0.8, znear: 0.1, zfar: 100
            ),
            sceneMin: min,
            sceneMax: max
        )
    }

    @Test
    func presetDistanceScalesThePageFitByTheVisibleExtent() {
        // 2 wide, 1 tall, 4 deep: the page's front fit sized the distance to 2.
        let box = state(min: [-1, -0.5, -2], max: [1, 0.5, 2])
        #expect(box.distance(framing: .front) == 10)
        #expect(box.distance(framing: .back) == 10)
        #expect(box.distance(framing: .left) == 20)
        #expect(box.distance(framing: .right) == 20)
        #expect(box.distance(framing: .top) == 20)
        #expect(abs(box.distance(framing: .isometric) - 10 * (21.0).squareRoot() / 2) < 1e-9)
    }

    @Test
    func flatBoxKeepsTheFittedDistance() {
        #expect(state(min: [0, 0, 0], max: [0, 0, 1]).distance(framing: .left) == 10)
    }

    @Test
    func presetAnglesMatchTheRealityKitViews() {
        // Page: azimuth follows RealityKit yaw; elevation is minus RealityKit pitch.
        #expect(CameraPreset.front.webOrbitAngles == (0, 0))
        #expect(CameraPreset.right.webOrbitAngles == (90, 0))
        #expect(CameraPreset.left.webOrbitAngles == (-90, 0))
        #expect(CameraPreset.back.webOrbitAngles == (180, 0))
        #expect(CameraPreset.top.webOrbitAngles == (0, -90))
        #expect(CameraPreset.bottom.webOrbitAngles == (0, 90))
        #expect(CameraPreset.isometric.webOrbitAngles == (35, -18))
    }
}
