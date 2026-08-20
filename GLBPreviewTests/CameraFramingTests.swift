import AppKit
import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct ThinAxisTests {
    @Test func doorLikeThinX() {
        #expect(PreviewCamera.thinAxis(SIMD3(0.05, 2.0, 0.8)) == 0)
    }

    @Test func doorLikeThinZ() {
        #expect(PreviewCamera.thinAxis(SIMD3(0.8, 2.0, 0.05)) == 2)
    }

    @Test func snowdropKeepsThreeQuarter() {
        #expect(PreviewCamera.thinAxis(SIMD3(1.83, 0.11, 0.47)) == nil)
    }

    @Test func cubeIsNotThin() {
        #expect(PreviewCamera.thinAxis(SIMD3(1, 1, 1)) == nil)
    }
}

struct FitCameraTests {
    @Test func standsOnPlusZForPlusZForwardModel() {
        let minBound = SIMD3<Float>(-1, -1, -1)
        let maxBound = SIMD3<Float>(1, 1, 1)
        let position = PreviewCamera.cameraPosition(
            minBound: minBound,
            maxBound: maxBound,
            padding: 1
        )
        #expect(position.z > 0)
        #expect(position.x > 0)
        #expect(position.y > 0)
    }

    @Test func thinZDecalCameraIsOnPlusZ() {
        let minBound = SIMD3<Float>(-1, -1, -0.01)
        let maxBound = SIMD3<Float>(1, 1, 0.01)
        let position = PreviewCamera.cameraPosition(
            minBound: minBound,
            maxBound: maxBound,
            padding: 1
        )
        #expect(position.z > 0)
        #expect(abs(position.x) < 0.01)
    }
}

@MainActor
struct FileCameraViewTests {
    @Test func copiesWorldPoseAndPerspectiveFOV() throws {
        let node = Entity()
        node.setPosition(SIMD3<Float>(1, 2, 3), relativeTo: nil)
        node.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        let preview = PerspectiveCamera()
        PreviewCamera.applyFileView(
            to: preview,
            cameraNode: node,
            spec: .init(
                name: "Front",
                type: "perspective",
                yfov: 0.7,
                znear: 0.1,
                zfar: 100,
                xmag: nil,
                ymag: nil
            )
        )
        let position = preview.position(relativeTo: nil)
        #expect(abs(position.x - 1) < 0.001)
        #expect(abs(position.y - 2) < 0.001)
        #expect(abs(position.z - 3) < 0.001)
        let camera = try #require(preview.components[PerspectiveCameraComponent.self])
        #expect(abs(camera.fieldOfViewInDegrees - 0.7 * 180 / .pi) < 0.01)
        #expect(preview.components[OrthographicCameraComponent.self] == nil)
    }

    @Test func appliesOrthographicScaleFromDocument() throws {
        let node = Entity()
        let preview = PerspectiveCamera()
        PreviewCamera.applyFileView(
            to: preview,
            cameraNode: node,
            spec: .init(
                name: "Ortho",
                type: "orthographic",
                yfov: nil,
                znear: 0.2,
                zfar: 50,
                xmag: 2,
                ymag: 1.5
            )
        )
        let camera = try #require(preview.components[OrthographicCameraComponent.self])
        #expect(abs(camera.scale - 1.5) < 0.0001)
        #expect(preview.components[PerspectiveCameraComponent.self] == nil)
    }

    @Test func fitRestoresPerspectiveAfterOrtho() throws {
        let preview = Entity()
        preview.components.set(OrthographicCameraComponent())
        PreviewCamera.restoreFitPerspective(on: preview)
        let camera = try #require(preview.components[PerspectiveCameraComponent.self])
        #expect(abs(camera.fieldOfViewInDegrees - 35) < 0.001)
        #expect(preview.components[OrthographicCameraComponent.self] == nil)
    }
}

struct ModelBoundsTests {
    @MainActor
    @Test func ignoresHelperWithoutMesh() async throws {
        let root = Entity()
        let model = ModelEntity(mesh: .generateBox(size: 1), materials: [SimpleMaterial()])
        model.position = .zero
        root.addChild(model)

        let helper = Entity()
        helper.position = SIMD3(100, 100, 100)
        helper.scale = SIMD3(50, 50, 50)
        root.addChild(helper)

        let bounds = PreviewCamera.modelBounds(of: root)
        let extent = bounds.max - bounds.min
        #expect(extent.x < 2)
        #expect(extent.y < 2)
        #expect(extent.z < 2)
    }

    @Test func unionDropsCmScaleLeftover() throws {
        var boxes: [BoundingBox] = (0..<8).map { i in
            let o = Float(i) * 0.2
            return BoundingBox(min: SIMD3(o, 0, 0), max: SIMD3(o + 1, 1, 1))
        }
        boxes.append(BoundingBox(min: SIMD3(-400, -700, -50), max: SIMD3(400, 700, 50)))
        let union = try #require(PreviewCamera.unionModelBoxes(boxes))
        let extent = union.max - union.min
        #expect(extent.x < 4)
        #expect(extent.y < 2)
        #expect(extent.z < 2)
    }

    @MainActor
    @Test func turntableCentersOffsetSketchfabRoot() {
        let root = Entity()
        root.position = SIMD3(409, -17, -36)
        let model = ModelEntity(mesh: .generateBox(size: 2), materials: [SimpleMaterial()])
        root.addChild(model)
        let assembled = PreviewCamera.makeTurntable(for: root)
        let bounds = PreviewCamera.modelBounds(of: assembled.pivot, relativeTo: assembled.pivot)
        #expect(abs(bounds.center.x) < 0.15)
        #expect(abs(bounds.center.y) < 0.15)
        #expect(abs(bounds.center.z) < 0.15)
        let extent = bounds.max - bounds.min
        #expect(extent.x > 1.5 && extent.x < 2.5)
    }

    @Test func unionKeepsEqualSizedTiles() throws {
        let boxes = (0..<6).map { i in
            let o = Float(i) * 200
            return BoundingBox(min: SIMD3(o, 0, 0), max: SIMD3(o + 180, 10, 180))
        }
        let union = try #require(PreviewCamera.unionModelBoxes(boxes))
        let extent = union.max - union.min
        #expect(extent.x > 1000)
    }
}
