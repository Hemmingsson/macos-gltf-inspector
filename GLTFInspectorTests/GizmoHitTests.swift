import simd
import Testing
@testable import Renderer

@Suite
struct GizmoHitTests {
    /// Front-facing ortho camera: world X maps horizontally across the view centre.
    private func frontOrthoViewProjection(aspect: Float = 1) -> simd_float4x4 {
        let pose = MetalCameraPose(azimuth: 0, elevation: 0, distance: 10, target: .zero,
                                   yfov: .pi / 4, znear: 0.1, zfar: 100,
                                   orthographic: MetalOrthographic(magnitude: 5, znear: 0.1, zfar: 100))
        let camera = MetalCamera(pose: pose, isOrthographic: true, aspect: aspect)
        return camera.openGLProjectionMatrix * camera.viewMatrix
    }

    @Test func pointWithinSlopHitsHorizontalSegment() {
        let vp = frontOrthoViewProjection()
        let viewport = GizmoHitViewport(width: 200, height: 200)
        let segments = [MetalGizmoSegment(a: SIMD3(-2, 0, 0), b: SIMD3(2, 0, 0), nodeIndex: 3)]
        let centre = SIMD2<Float>(100, 100)
        #expect(gizmoHit(at: centre, segments: segments, viewProjection: vp, viewport: viewport) == 3)
        #expect(gizmoHit(at: centre + SIMD2(0, 5.9), segments: segments, viewProjection: vp, viewport: viewport) == 3)
        #expect(gizmoHit(at: centre + SIMD2(0, 6.1), segments: segments, viewProjection: vp, viewport: viewport) == nil)
    }

    @Test func zeroLengthProjectedSegmentHitsNearPoint() {
        let vp = frontOrthoViewProjection()
        let viewport = GizmoHitViewport(width: 100, height: 100)
        let segments = [MetalGizmoSegment(a: SIMD3(0, 0, 0), b: SIMD3(0, 0, 0), nodeIndex: 7)]
        #expect(gizmoHit(at: SIMD2(50, 50), segments: segments, viewProjection: vp, viewport: viewport) == 7)
        #expect(gizmoHit(at: SIMD2(56, 50), segments: segments, viewProjection: vp, viewport: viewport) == 7)
        #expect(gizmoHit(at: SIMD2(57, 50), segments: segments, viewProjection: vp, viewport: viewport) == nil)
    }

    @Test func nearestSegmentWinsAndTieBreaksToLowerNodeIndex() {
        let vp = frontOrthoViewProjection()
        let viewport = GizmoHitViewport(width: 200, height: 200)
        let segments = [
            MetalGizmoSegment(a: SIMD3(-2, 0.05, 0), b: SIMD3(2, 0.05, 0), nodeIndex: 5),
            MetalGizmoSegment(a: SIMD3(-2, -0.05, 0), b: SIMD3(2, -0.05, 0), nodeIndex: 2),
        ]
        #expect(gizmoHit(at: SIMD2(100, 100), segments: segments, viewProjection: vp, viewport: viewport) == 2)
        let tieSegments = [
            MetalGizmoSegment(a: SIMD3(-2, 0, 0), b: SIMD3(2, 0, 0), nodeIndex: 9),
            MetalGizmoSegment(a: SIMD3(-2, 0, 0), b: SIMD3(2, 0, 0), nodeIndex: 4),
        ]
        #expect(gizmoHit(at: SIMD2(100, 100), segments: tieSegments, viewProjection: vp, viewport: viewport) == 4)
    }

    @Test func hitSlopIsSixViewPointsNotPixels() {
        let vp = frontOrthoViewProjection()
        let viewport = GizmoHitViewport(width: 100, height: 100)
        let segments = [MetalGizmoSegment(a: SIMD3(-2, 0, 0), b: SIMD3(2, 0, 0), nodeIndex: 1)]
        let centre = SIMD2<Float>(50, 50)
        #expect(gizmoHit(at: centre + SIMD2(0, 6), segments: segments, viewProjection: vp, viewport: viewport) == 1)
        #expect(gizmoHit(at: centre + SIMD2(0, 6.01), segments: segments, viewProjection: vp, viewport: viewport) == nil)
    }

    @Test func behindCameraSegmentIsNotSelectable() {
        let pose = MetalCameraPose(azimuth: 0, elevation: 0, distance: 5, target: .zero,
                                   yfov: .pi / 4, znear: 0.1, zfar: 100)
        let camera = MetalCamera(pose: pose, isOrthographic: false, aspect: 1)
        let vp = camera.openGLProjectionMatrix * camera.viewMatrix
        let viewport = GizmoHitViewport(width: 100, height: 100)
        let segments = [MetalGizmoSegment(a: SIMD3(0, 0, 6), b: SIMD3(1, 0, 6), nodeIndex: 1)]
        #expect(gizmoHit(at: SIMD2(50, 50), segments: segments, viewProjection: vp, viewport: viewport) == nil)
    }

    @Test func sceneGizmosOverlaySegmentsAreNonEmptyForFixtures() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cameras)
        let scene = try #require(renderer.scene)
        let cameraSegments = overlayGizmoSegments(scene: scene, options: MetalOverlayOptions(sceneGizmos: true))
        #expect(!cameraSegments.isEmpty)
        try await renderer.load(url: TestFixtures.lights)
        let lightScene = try #require(renderer.scene)
        let lightSegments = overlayGizmoSegments(scene: lightScene, options: MetalOverlayOptions(sceneGizmos: true))
        #expect(!lightSegments.isEmpty)
    }

    @Test func overlayGizmoSegmentsEmptyWhenSceneGizmosOff() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cameras)
        let scene = try #require(renderer.scene)
        #expect(overlayGizmoSegments(scene: scene, options: MetalOverlayOptions(sceneGizmos: false)).isEmpty)
    }
}
