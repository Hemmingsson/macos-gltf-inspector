import Foundation
import GLTFCore
import simd
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct SceneGizmoTests {
    private func fixture(_ edit: (inout [String: Any]) -> Void) throws -> URL {
        var json = try GLBBox.peekDocumentJSON(from: TestFixtures.cameras)
        edit(&json)
        return try TestGLB.writeTempGLB(json: json, prefix: "scene-gizmo")
    }

    private func positions(_ vertices: [MetalLineVertex]) -> [SIMD3<Float>] {
        vertices.map { SIMD3($0.position.x, $0.position.y, $0.position.z) }
    }

    private func segments(_ vertices: [MetalLineVertex]) -> [(SIMD3<Float>, SIMD3<Float>)] {
        stride(from: 0, to: vertices.count - vertices.count % 2, by: 2).map {
            let a = vertices[$0].position, b = vertices[$0 + 1].position
            return (SIMD3(a.x, a.y, a.z), SIMD3(b.x, b.y, b.z))
        }
    }

    private func undirectedEdgeKeys(_ vertices: [MetalLineVertex], tolerance: Float = 1e-4) -> Set<String> {
        func key(_ p: SIMD3<Float>) -> String {
            let r = round(p / tolerance) * tolerance
            return "\(r.x),\(r.y),\(r.z)"
        }
        var edges = Set<String>()
        for (a, b) in segments(vertices) {
            let ka = key(a), kb = key(b)
            edges.insert(ka < kb ? "\(ka)|\(kb)" : "\(kb)|\(ka)")
        }
        return edges
    }
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

    @Test func pointLightOctahedronHasTwelveEdgesAtAuthoredRadius() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.lights)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 0))
        #expect(undirectedEdgeKeys(vertices).count == 12, "a point light is a 12-edge octahedron")
        let radius: Float = 0.03
        for p in positions(vertices) {
            #expect(abs(simd_length(p) - radius) < 1e-4 || simd_length(p) < 1e-4,
                    "every octahedron endpoint lies on the 0.03×span sphere or at the origin")
        }
    }

    @Test func directionalPlateIsPerpendicularToItsRay() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.lights)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 1))
        let direction = SIMD3<Float>(0, 0, -1)
        let segs = segments(vertices)
        let ray = segs.first { simd_distance($0.0, $0.1) >= 0.49 }
        #expect(ray != nil, "the direction ray must span half the unit scene")
        if let ray {
            let delta = simd_normalize(ray.1 - ray.0)
            #expect(abs(simd_dot(delta, direction) - 1) < 0.02 || abs(simd_dot(delta, direction) + 1) < 0.02)
        }
        let plateEdges = segs.filter { len in
            let d = len.1 - len.0
            let l = simd_length(d)
            return l > 0.02 && l < 0.06
        }
        #expect(!plateEdges.isEmpty)
        for edge in plateEdges {
            let delta = simd_normalize(edge.1 - edge.0)
            #expect(abs(simd_dot(delta, direction)) < 0.05, "plate edges must lie in the plane ⊥ to direction")
        }
    }

    @Test func spotLightBaseUsesItsOuterConeAngleAndRangeFallback() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.lights)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 2))
        // No range: L = 0.25 × the unit mesh extent. The light is at (0,2,0).
        let L: Float = 0.25
        let outerRadius = L * tan(Float(0.6))
        let innerRadius = L * tan(Float(0.2))
        let baseTip = SIMD4<Float>(outerRadius, 2, -L, 1)
        let innerRing = SIMD4<Float>(innerRadius, 2, -L, 1)
        #expect(vertices.contains { simd_distance($0.position, baseTip) < 1e-5 },
                "spot outer ring must be L × tan(outerConeAngle) at distance L down -Z")
        #expect(vertices.contains { simd_distance($0.position, innerRing) < 1e-5 },
                "spot inner ring must share the same base plane at L × tan(innerConeAngle)")
        let axisEnd = SIMD4<Float>(0, 2, -L * 0.92, 1)
        #expect(vertices.contains { simd_distance($0.position, axisEnd) < 1e-5 },
                "the axis line must stop just short of the base circle")
        #expect(vertices.count >= 138, "two 32-segment rings, four generators and an axis need at least 138 vertices")
    }

    @Test func sceneGizmosDrawEveryLightUnlessHidden() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.lights)
        let scene = try #require(renderer.scene)
        let all = overlayVertices(scene: scene, options: MetalOverlayOptions(sceneGizmos: true))
        #expect(all.contains { simd_distance($0.position, SIMD4(0.03, 0, 0, 1)) < 1e-5 })
        #expect(all.contains { simd_distance($0.position, SIMD4(0, 0, -0.5, 1)) < 1e-5 })
        let L: Float = 0.25
        #expect(all.contains { simd_distance($0.position, SIMD4(L * tan(0.6), 2, -L, 1)) < 1e-5 })

        let hiddenSun = overlayVertices(scene: scene,
                                        options: MetalOverlayOptions(sceneGizmos: true, hiddenNodeIndices: [1]))
        #expect(!hiddenSun.contains { simd_distance($0.position, SIMD4(0, 0, -0.5, 1)) < 1e-5 })
        #expect(hiddenSun.contains { simd_distance($0.position, SIMD4(0.03, 0, 0, 1)) < 1e-5 })
    }

    @Test func selectedLightDrawsWhenSceneGizmosAreOff() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.lights)
        let scene = try #require(renderer.scene)
        let vertices = overlayVertices(scene: scene, options: MetalOverlayOptions(sceneGizmos: false, selectedNode: 0))
        #expect(vertices.contains { simd_distance($0.position, SIMD4(0.03, 0, 0, 1)) < 1e-5 })
    }

    @Test func skeletonShowsACrossAtEveryJointAsWellAsTheBone() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.rigged)
        let vertices = overlayVertices(scene: try #require(renderer.scene), options: MetalOverlayOptions(selectedNode: 2))
        #expect(vertices.count >= 14, "two joints need three cross segments each in addition to their connecting bone")
    }

    @Test func nestedGroupSelectionShowsItsDescendantBox() async throws {
        let url = try writeTempNestedGroupedMeshGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let vertices = overlayVertices(
            scene: try #require(renderer.scene),
            options: MetalOverlayOptions(selectedNode: 1)
        )
        #expect(vertices.count == 24, "a non-joint group needs its 12-edge subtree box")
        #expect(vertices.contains { $0.position.x > 9 })
    }

    @Test func gizmosExcludeCamerasOutsideTheLoadedScene() async throws {
        let url = try fixture { json in
            json["scenes"] = [["nodes": [0]], ["nodes": [1, 2]]]
            json["scene"] = 0
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let segments = overlayGizmoSegments(scene: try #require(renderer.scene),
                                            options: MetalOverlayOptions(sceneGizmos: true))
        #expect(segments.isEmpty, "neither camera belongs to the loaded scene")
    }

    @Test func gizmosExcludeAuthoredHiddenCameras() async throws {
        let url = try fixture { json in
            var nodes = json["nodes"] as! [[String: Any]]
            nodes[1]["extensions"] = ["KHR_node_visibility": ["visible": false]]
            json["nodes"] = nodes
            json["extensionsUsed"] = ["KHR_node_visibility"]
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let segments = overlayGizmoSegments(scene: try #require(renderer.scene),
                                            options: MetalOverlayOptions(sceneGizmos: true))
        #expect(!segments.contains { $0.nodeIndex == 1 })
    }

    @Test func gizmosExcludeCamerasUnderAuthoredHiddenParent() async throws {
        let url = try fixture { json in
            var nodes = json["nodes"] as! [[String: Any]]
            nodes[0]["children"] = [1]
            nodes[1]["extensions"] = ["KHR_node_visibility": ["visible": false]]
            nodes[1]["children"] = [2]
            json["nodes"] = nodes
            json["scenes"] = [["nodes": [0]]]
            json["extensionsUsed"] = ["KHR_node_visibility"]
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let segments = overlayGizmoSegments(scene: try #require(renderer.scene),
                                            options: MetalOverlayOptions(sceneGizmos: true))
        #expect(!segments.contains { $0.nodeIndex == 2 })
    }
}
