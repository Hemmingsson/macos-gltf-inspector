import Foundation
import Testing
import simd
@testable import GLBPreview

struct PreviewOrientationGizmoTests {
    @Test func identityCameraProjectsWorldXRightAndYUp() throws {
        let origin = CGPoint(x: 20, y: 46)
        let axes = PreviewOrientationGizmo.projectedAxes(
            cameraOrientation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            origin: origin,
            length: 26
        )
        let byLabel = Dictionary(uniqueKeysWithValues: axes.map { ($0.label, $0) })
        let x = try #require(byLabel["X"])
        let y = try #require(byLabel["Y"])
        let z = try #require(byLabel["Z"])

        #expect(abs(x.tip.x - (origin.x + 26)) < 0.01)
        #expect(abs(x.tip.y - origin.y) < 0.01)
        #expect(abs(y.tip.x - origin.x) < 0.01)
        #expect(abs(y.tip.y - (origin.y - 26)) < 0.01)
        // +Z toward viewer at identity — drawn last (nearest).
        #expect(z.depth > x.depth)
        #expect(axes.last?.label == "Z")
    }

    @Test func yaw90MovesWorldZOntoScreenLeft() throws {
        // Camera yaw +90° around Y: look along world −X. World +Z → camera −X (screen left).
        let yaw = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        let origin = CGPoint(x: 20, y: 46)
        let axes = PreviewOrientationGizmo.projectedAxes(
            cameraOrientation: yaw,
            origin: origin,
            length: 26
        )
        let byLabel = Dictionary(uniqueKeysWithValues: axes.map { ($0.label, $0) })
        let x = try #require(byLabel["X"])
        let z = try #require(byLabel["Z"])

        #expect(abs(x.tip.x - origin.x) < 0.5)
        #expect(abs(x.tip.y - origin.y) < 0.5)
        #expect(abs(z.tip.x - (origin.x - 26)) < 0.5)
        #expect(abs(z.tip.y - origin.y) < 0.5)
    }
}
