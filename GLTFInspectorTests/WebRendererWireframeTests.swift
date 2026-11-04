import AppKit
import Foundation
import GLTFCore
import Testing
@testable import RendererWebKit

/// Wireframe must not rebuild every triangle edge on the CPU each frame, and a skinned
/// mesh must deform (the old overlay used rest-pose positions × node world matrix).
@MainActor
struct WebRendererWireframeTests {
    private func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    @Test
    func wireframeDoesNotRebuildEdgesEveryFrame() async throws {
        let host = try await WebKitTest.stillHost(size: 128)
        _ = try await host.load(model: TestFixtures.cube)
        try await host.apply(WebPreviewCanvas.Look(viewMode: .wireframe))
        _ = try await host.renderStill()
        let afterFirst = try await host.stats()
        _ = try await host.renderStill()
        let afterSecond = try await host.stats()

        #expect(
            afterFirst.wireframePath == "polygonMode" || afterFirst.wireframePath == "cachedLines",
            "wireframe still uses the per-frame CPU edge rebuild (\(afterFirst.wireframePath))"
        )
        #expect(
            afterSecond.wireframeCollects == afterFirst.wireframeCollects,
            "collectWireframe ran again on a still (\(afterFirst.wireframeCollects) → \(afterSecond.wireframeCollects))"
        )
        #expect(afterSecond.wireframeCollects <= 1)
    }

    /// Hip joint of `two-joint-skin` (every vertex is weighted to joint 0). Rest-pose
    /// overlay would ignore this rotation.
    @Test
    func wireframeSkinnedMeshDeforms() async throws {
        let host = try await WebKitTest.stillHost(size: 160)
        _ = try await host.load(model: TestFixtures.rigged)
        try await host.apply(WebPreviewCanvas.Look(viewMode: .wireframe))
        let rest = try await host.renderStill()

        _ = try await host.evaluate(
            "(window.__viewer.poseNode({index:1,rotation:[0,0,0.70710678,0.70710678]}).ok)"
        )
        let posed = try await host.renderStill()

        #expect(png(rest) != nil && png(posed) != nil)
        #expect(png(rest) != png(posed), "wireframe ignored the skinned joint")
    }
}
