import Foundation
import simd
import Testing
@testable import Renderer

struct MetalCameraTests {
    private func camera(azimuth: Double = 0, elevation: Double = 0) -> MetalCamera {
        MetalCamera(pose: MetalCameraPose(
            azimuth: azimuth, elevation: elevation, distance: 5, target: SIMD3(1, 2, 3),
            yfov: .pi / 3, znear: 0.5, zfar: 100
        ))
    }

    @Test func frontPoseLooksAlongNegativeZAtRecordedTarget() {
        let camera = camera()
        #expect(simd_distance(camera.eye, SIMD3(1, 2, 8)) < 0.00001)
        let targetInView = camera.viewMatrix * SIMD4(camera.pose.target, 1)
        #expect(simd_distance(targetInView, SIMD4(0, 0, -5, 1)) < 0.00001)
    }

    @Test func positiveAzimuthLooksFromRightAndNegativeElevationFromAbove() {
        #expect(simd_distance(camera(azimuth: 90).eye, SIMD3(6, 2, 3)) < 0.00001)
        #expect(simd_distance(camera(elevation: -90).eye, SIMD3(1, 7, 3)) < 0.00001)
        let orbit = camera(azimuth: 25, elevation: -18)
        let targetInView = orbit.viewMatrix * SIMD4(orbit.pose.target, 1)
        #expect(simd_distance(targetInView, SIMD4(0, 0, -5, 1)) < 0.00001)
    }

    @Test(arguments: [MetalCamera.Projection.perspective, .orthographic])
    func depthRangeMapsNearToZeroAndFarToOne(_ projection: MetalCamera.Projection) {
        var camera = camera()
        camera.projection = projection
        let near = camera.projectionMatrix * SIMD4<Float>(0, 0, -0.5, 1)
        let far = camera.projectionMatrix * SIMD4<Float>(0, 0, -100, 1)
        #expect(abs(near.z / near.w) < 0.00001)
        #expect(abs(far.z / far.w - 1) < 0.00001)
    }

    @Test func orthographicMagnificationMatchesPerspectiveAtTargetDistance() {
        var perspective = camera()
        perspective.aspect = 1.5
        var orthographic = perspective
        orthographic.projection = .orthographic
        let point = SIMD4<Float>(0, 1, -5, 1)
        let p = perspective.projectionMatrix * point
        let o = orthographic.projectionMatrix * point
        #expect(abs(p.y / p.w - o.y / o.w) < 0.00001)
        // This apparently unusual aspect rule is part of the page's pinned projection.
        #expect(orthographic.projectionMatrix.columns.0.x == orthographic.projectionMatrix.columns.1.y)
    }

    @Test func perspectiveCanReplayAnInfiniteFarPlane() {
        var camera = camera()
        camera.pose.zfar = .infinity
        let near = camera.projectionMatrix * SIMD4<Float>(0, 0, -0.5, 1)
        #expect(abs(near.z / near.w) < 0.00001)
        #expect(camera.projectionMatrix.columns.2.z == -1)
        #expect(camera.projectionMatrix.columns.3.z == -0.5)
    }
}
