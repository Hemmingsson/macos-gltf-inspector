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
    /// Waits for the controller to leave `.loading`. The live page reports a load in well under
    /// the host's 15 s timeout; the cap only keeps a regression from hanging the suite.
    private func settledPhase(
        of canvas: WebCanvasController,
        within limit: Duration = .seconds(30)
    ) async throws -> WebCanvasController.Phase {
        let deadline = ContinuousClock.now + limit
        while canvas.phase == .loading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return canvas.phase
    }

    private func mount(_ canvas: WebCanvasController, url: URL) -> NSView {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        canvas.attach(
            to: container, url: url, look: WebPreviewCanvas.Look(), placeholder: nil, existing: nil
        )
        return container
    }

    @Test
    func corruptFileEndsInFailedNotASpinner() async throws {
        let canvas = WebCanvasController()
        _ = mount(canvas, url: TestFixtures.corrupt)

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
        _ = mount(canvas, url: TestFixtures.cube)
        #expect(try await settledPhase(of: canvas) == .ready)

        try await canvas.fit()
        try await canvas.apply(preset: .top)
        let top = try await canvas.snapshot()
        try await canvas.apply(preset: .right)
        let right = try await canvas.snapshot()
        try await canvas.reset()

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
        let first = mount(canvas, url: TestFixtures.cube)
        #expect(try await settledPhase(of: canvas) == .ready)
        let webView = try #require(first.subviews.first { $0.className.contains("WKWebView") })

        WebPreviewCanvas.dismantleNSView(first, coordinator: canvas)
        let second = mount(canvas, url: TestFixtures.cube)

        #expect(webView.superview === second)
        #expect(canvas.phase == .ready)
        // Same page, still drawing: commands and a frame work without a second load.
        try await canvas.fit()
        let frame = try await canvas.snapshot()
        #expect(frame.width > 1)
    }

    @Test
    func timedOutHostFailsFastAfterwards() async throws {
        let host = try WebRendererHost(mode: .still, timeout: .milliseconds(1))
        await #expect(throws: WebRendererError.timedOut) {
            try await host.start(size: 64)
        }
        #expect(host.isBroken)
        await #expect(throws: WebRendererError.timedOut) {
            try await host.send { .fit(id: $0) }
        }
    }
}

/// Pure preset math — no web view.
struct WebCameraPresetTests {
    private func state(min: [Double], max: [Double], distance: Double = 10) -> RendererCameraState {
        RendererCameraState(json: [
            "camera": [
                "azimuth": 0.0, "elevation": 0.0, "distance": distance,
                "target": [0.0, 0.0, 0.0], "yfov": 0.8, "znear": 0.1, "zfar": 100.0,
            ] as [String: Any],
            "sceneMin": min,
            "sceneMax": max,
        ])!
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
