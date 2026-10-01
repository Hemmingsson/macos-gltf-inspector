import Foundation
import GLTFCore
import simd
import Testing

/// Shared Fit distance: projected AABB + near-face depth + `fitPadding`.
struct RenderCameraTests {
    @Test func fitDistanceAddsPaddingAndNearFaceDepth() {
        let extent = SIMD3<Float>(1, 1, 1)
        let front = RenderCamera.fitDistance(
            extent: extent,
            toCamera: SIMD3(0, 0, 1),
            aspect: 1,
            fieldOfViewInDegrees: 35
        )
        let vHalf = RenderCamera.defaultFieldOfViewDegrees * .pi / 360
        let projected = Float(0.5) / tan(vHalf)
        let unpadded = projected + 0.5
        #expect(abs(front - unpadded * RenderCamera.fitPadding) < 0.0001)
        #expect(front > projected * 1.2)
    }

    @Test func lookDirectionFrontIsPlusZ() {
        let front = RenderCamera.lookDirection(azimuthDegrees: 0, elevationDegrees: 0)
        #expect(abs(front.x) < 0.0001)
        #expect(abs(front.y) < 0.0001)
        #expect(abs(front.z - 1) < 0.0001)
    }
}
