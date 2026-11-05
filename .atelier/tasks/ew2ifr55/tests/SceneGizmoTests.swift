import simd
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct SceneGizmoTests {
    // Backlog y3hdxwwh: a selected camera is visible even with the global gizmo toggle off.
    @Test func selectedPerspectiveCameraHasFrustumEdgesAtItsAuthoredPosition() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cameras)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 1))
        #expect(vertices.count >= 16, "the selected perspective camera needs four rays and four rectangle edges")
        #expect(vertices.contains { simd_distance($0.position, SIMD4<Float>(0, 0, 3, 1)) < 1e-5 },
                "the frustum apex must be the authored camera position")
    }

    // Backlog umczfxl2: the directional light's node has no mesh bounds to outline.
    @Test func selectedDirectionalLightHasAPlateAndDirectionLine() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.lights)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 1))
        #expect(vertices.count >= 10, "a selected directional light needs a four-edge plate and a direction line")
        let longest = stride(from: 0, to: vertices.count - vertices.count % 2, by: 2).map {
            simd_distance(vertices[$0].position, vertices[$0 + 1].position)
        }.max() ?? 0
        #expect(longest >= 0.49, "the direction ray must span half the unit-sized scene, not a tiny selection box")
    }

    // Backlog fnaam6pc: selecting the knee must show its connection to the hip.
    @Test func selectedJointShowsItsBoneToTheParentJoint() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.rigged)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 2))
        let segments = stride(from: 0, to: vertices.count - vertices.count % 2, by: 2).map {
            (vertices[$0].position, vertices[$0 + 1].position)
        }
        let hip = SIMD4<Float>(0, 0, 0, 1), knee = SIMD4<Float>(0, 1, 0, 1)
        #expect(segments.contains { a, b in
            (simd_distance(a, hip) < 1e-5 && simd_distance(b, knee) < 1e-5)
                || (simd_distance(b, hip) < 1e-5 && simd_distance(a, knee) < 1e-5)
        }, "selecting a joint must show the bone, even though the joint itself has no mesh")
    }

    @Test func noSelectionAndDefaultOptionsEmitNoGizmos() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cameras)
        #expect(overlayVertices(scene: try #require(renderer.scene), options: MetalOverlayOptions()).isEmpty)
    }

    @Test func perspectiveFrustumUsesTheSpecifiedDisplayPlaneAndHasAnUpTriangle() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cameras)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 1))
        // Mesh bounds are [0,1]×[0,1]×0; d = max(0.15 × extent, znear) = 0.15.
        let d: Float = 0.15
        let halfHeight = d * tan(Float(0.7) / 2)
        let corner = SIMD4<Float>(halfHeight, halfHeight, 3 - d, 1)
        #expect(vertices.contains { simd_distance($0.position, corner) < 1e-5 },
                "perspective corners must use the authored FOV and specified display distance")
        #expect(vertices.contains { abs($0.position.z - (3 - d)) < 1e-5 && $0.position.y > halfHeight + 1e-5 },
                "the up triangle must extend above the display rectangle")
    }

    @Test func selectedOrthographicCameraUsesItsAuthoredMagnification() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cameras)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 2))
        // Camera at (3,0,0), xmag = ymag = 1, znear = 0.1, no authored rotation.
        for x: Float in [2, 4] {
            for y: Float in [-1, 1] {
                let corner = SIMD4<Float>(x, y, -0.1, 1)
                #expect(vertices.contains { simd_distance($0.position, corner) < 1e-5 },
                        "orthographic near-plane corners must use the authored half magnifications")
            }
        }
    }

    @Test func directionalRayFollowsTheAuthoredNegativeZDirection() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.lights)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 1))
        #expect(vertices.contains { simd_distance($0.position, SIMD4<Float>(0, 0, -0.5, 1)) < 1e-5 },
                "an unrotated glTF light points down local -Z")
    }

    @Test func pointLightHasAllSixOctahedronTips() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.lights)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 0))
        for axis in 0..<3 {
            for sign: Float in [-1, 1] {
                var tip = SIMD4<Float>(0, 0, 0, 1)
                tip[axis] = sign * 0.03
                #expect(vertices.contains { simd_distance($0.position, tip) < 1e-5 },
                        "the point light's octahedron must have tips on all six signed axes")
            }
        }
    }

    @Test func spotLightBaseUsesItsOuterConeAngleAndRangeFallback() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.lights)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 2))
        // No range: L = 0.25 × the unit mesh extent. The light is at (0,2,0).
        let radius = Float(0.25) * tan(Float(0.6))
        let baseTip = SIMD4<Float>(radius, 2, -0.25, 1)
        #expect(vertices.contains { simd_distance($0.position, baseTip) < 1e-5 },
                "spot radius must be L × tan(outerConeAngle) at distance L down -Z")
        #expect(vertices.count >= 138, "two 32-segment rings, four generators and an axis need at least 138 vertices")
    }

    @Test func skeletonShowsACrossAtEveryJointAsWellAsTheBone() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.rigged)
        let vertices = overlayVertices(scene: try #require(renderer.scene), options: MetalOverlayOptions(selectedNode: 2))
        #expect(vertices.count >= 14, "two joints need three cross segments each in addition to their connecting bone")
    }
}
