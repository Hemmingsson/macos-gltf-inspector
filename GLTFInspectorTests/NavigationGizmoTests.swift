import Foundation
import simd
import Testing
@testable import GLTFInspector
import Renderer

struct NavigationGizmoTests {
    private let panel = CGSize(width: 76, height: 76)

    @Test func ballLayoutsDepthSortPutsFartherEndsFirst() {
        // Identity view rotation: +Z toward the viewer draws on top of -Z.
        let layouts = NavigationGizmoLayout.ballLayouts(viewRotation: matrix_identity_float3x3, panelSize: panel)
        let sorted = NavigationGizmoLayout.sortedForDrawing(layouts)
        let depths = sorted.map(\.viewDepth)
        #expect(depths == depths.sorted(), "draw order must be back-to-front by view-space z")
        let front = layouts.first { $0.axis == .posZ }
        let back = layouts.first { $0.axis == .negZ }
        #expect(front != nil && back != nil)
        #expect(front!.viewDepth > back!.viewDepth, "+Z should be closer than −Z at identity")
        #expect(sorted.last?.axis == .posZ)
    }

    @Test func rotatedViewReordersAxisEnds() {
        var rotation = matrix_identity_float3x3
        rotation.columns.2 = SIMD3(0, 0, -1)
        rotation.columns.0 = SIMD3(-1, 0, 0)
        let sorted = NavigationGizmoLayout.sortedForDrawing(
            NavigationGizmoLayout.ballLayouts(viewRotation: rotation, panelSize: panel)
        )
        #expect(sorted.first?.axis != sorted.last?.axis)
    }

    @Test(arguments: [
        (NavigationAxis.posX, CameraPreset.right),
        (.negX, .left),
        (.posY, .top),
        (.negY, .bottom),
        (.posZ, .front),
        (.negZ, .back),
    ])
    func axisMapsToCameraPreset(axis: NavigationAxis, preset: CameraPreset) {
        #expect(axis.cameraPreset == preset)
    }

    @Test func selectingActivePresetFlipsToOpposite() {
        #expect(NavigationGizmoLayout.cameraPreset(for: .posZ, activePreset: .front) == .back)
        #expect(NavigationGizmoLayout.cameraPreset(for: .posX, activePreset: .right) == .left)
        #expect(NavigationGizmoLayout.cameraPreset(for: .posY, activePreset: nil) == .top)
        #expect(NavigationGizmoLayout.cameraPreset(for: .posZ, activePreset: .back) == .front)
    }
}
