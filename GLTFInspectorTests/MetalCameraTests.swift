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

    /// WebGL clip space: the near plane maps to -1 and the far plane to +1.
    @Test(arguments: [false, true])
    func depthRangeMapsNearToMinusOneAndFarToOne(_ isOrthographic: Bool) {
        var camera = camera()
        camera.isOrthographic = isOrthographic
        let near = camera.openGLProjectionMatrix * SIMD4<Float>(0, 0, -0.5, 1)
        let far = camera.openGLProjectionMatrix * SIMD4<Float>(0, 0, -100, 1)
        #expect(abs(near.z / near.w + 1) < 0.0001)
        #expect(abs(far.z / far.w - 1) < 0.0001)
    }

    @Test func orthographicMagnificationMatchesPerspectiveAtTargetDistance() {
        var perspective = camera()
        perspective.aspect = 1.5
        var orthographic = perspective
        orthographic.isOrthographic = true
        let point = SIMD4<Float>(0, 1, -5, 1)
        let p = perspective.openGLProjectionMatrix * point
        let o = orthographic.openGLProjectionMatrix * point
        #expect(abs(p.y / p.w - o.y / o.w) < 0.00001)
        // The Khronos viewer assigns the same xmag and ymag, whatever the canvas aspect.
        #expect(orthographic.openGLProjectionMatrix.columns.0.x == orthographic.openGLProjectionMatrix.columns.1.y)
    }

    @Test func perspectiveCanReplayAnInfiniteFarPlane() {
        var camera = camera()
        camera.pose.zfar = .infinity
        let near = camera.openGLProjectionMatrix * SIMD4<Float>(0, 0, -0.5, 1)
        #expect(abs(near.z / near.w + 1) < 0.0001)
        #expect(camera.openGLProjectionMatrix.columns.2.z == -1)
        #expect(camera.openGLProjectionMatrix.columns.3.z == -1)
    }
}
