import Foundation
import GLTFCore
import simd
import Testing
@testable import RendererWebKit

/// WebKit open / Fit must use the same projected-AABB + padding rule as RealityKit.
@MainActor
struct WebRendererFitTests {
    @Test func initialFitUsesSharedPaddingRule() async throws {
        let host = try await WebKitTest.stillHost(size: 512)
        _ = try await host.load(model: TestFixtures.cube)
        let opened = try await host.camera(.get)
        try assertFit(opened, aspect: 1)

        let fitted = try await host.camera(.fit)
        try assertFit(fitted, aspect: 1)
    }

    @Test func boxAnimatedFitUsesSharedPaddingRule() async throws {
        let host = try await WebKitTest.stillHost(size: 512)
        _ = try await host.load(model: TestFixtures.boxAnimated)
        let fitted = try await host.camera(.fit)
        try assertFit(fitted, aspect: 1)
    }

    private func assertFit(_ state: RendererCameraState, aspect: Float) throws {
        #expect(state.isMeasurable)
        let extent = SIMD3<Float>(
            Float(state.sceneMax[0] - state.sceneMin[0]),
            Float(state.sceneMax[1] - state.sceneMin[1]),
            Float(state.sceneMax[2] - state.sceneMin[2])
        )
        let toCamera = RenderCamera.lookDirection(
            azimuthDegrees: state.pose.azimuth,
            elevationDegrees: state.pose.elevation
        )
        let expected = RenderCamera.fitDistance(
            extent: extent,
            toCamera: toCamera,
            aspect: aspect,
            fieldOfViewInDegrees: Float(state.pose.yfov * 180 / .pi)
        )
        let actual = Float(state.pose.distance)
        #expect(
            abs(actual - expected) <= max(0.02, expected * 0.03),
            "fit distance \(actual) != shared rule \(expected)"
        )
    }
}
