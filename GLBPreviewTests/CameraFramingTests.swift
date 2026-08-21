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

    @Test func thinAxisOverrideCanBeDisabledForPresets() {
        let minBound = SIMD3<Float>(-1, -1, -0.01)
        let maxBound = SIMD3<Float>(1, 1, 0.01)
        // Thin Z would force yaw=0; with override off, right preset stays on +X.
        let position = PreviewCamera.cameraPosition(
            minBound: minBound,
            maxBound: maxBound,
            padding: 1,
            yaw: PreviewCamera.CameraPreset.right.yawDegrees,
            pitch: PreviewCamera.CameraPreset.right.pitchDegrees,
            applyThinAxisOverride: false
        )
        #expect(position.x > 0)
        #expect(abs(position.z) < 0.01)
    }
}

struct CameraPresetTests {
    @Test func angleTableMatchesPillCopy() {
        #expect(PreviewCamera.CameraPreset.front.yawDegrees == 0)
        #expect(PreviewCamera.CameraPreset.front.pitchDegrees == 0)
        #expect(PreviewCamera.CameraPreset.back.yawDegrees == 180)
        #expect(PreviewCamera.CameraPreset.left.yawDegrees == -90)
        #expect(PreviewCamera.CameraPreset.right.yawDegrees == 90)
        #expect(PreviewCamera.CameraPreset.top.pitchDegrees == 90)
        #expect(PreviewCamera.CameraPreset.bottom.pitchDegrees == -90)
        #expect(PreviewCamera.CameraPreset.iso.yawDegrees == PreviewCamera.yawDegrees)
        #expect(PreviewCamera.CameraPreset.iso.pitchDegrees == PreviewCamera.pitchDegrees)
        #expect(PreviewCamera.CameraPreset.allCases.count == 7)
    }

    @Test func frontPlacesCameraOnPlusZ() {
        let minBound = SIMD3<Float>(-0.5, -0.5, -0.5)
        let maxBound = SIMD3<Float>(0.5, 0.5, 0.5)
        let p = PreviewCamera.CameraPreset.front
        let position = PreviewCamera.cameraPosition(
            minBound: minBound,
            maxBound: maxBound,
            padding: 1,
            yaw: p.yawDegrees,
            pitch: p.pitchDegrees,
            applyThinAxisOverride: false
        )
        #expect(position.z > 0)
        #expect(abs(position.x) < 0.01)
        #expect(abs(position.y) < 0.01)
    }

    @Test func topPlacesCameraOnPlusY() {
        let minBound = SIMD3<Float>(-0.5, -0.5, -0.5)
        let maxBound = SIMD3<Float>(0.5, 0.5, 0.5)
        let p = PreviewCamera.CameraPreset.top
        let position = PreviewCamera.cameraPosition(
            minBound: minBound,
            maxBound: maxBound,
            padding: 1,
            yaw: p.yawDegrees,
            pitch: p.pitchDegrees,
            applyThinAxisOverride: false
        )
        #expect(position.y > 0)
        #expect(abs(position.x) < 0.01)
        #expect(abs(position.z) < 0.01)
    }

    @Test func backLeftRightBottomAxes() {
        let minBound = SIMD3<Float>(-0.5, -0.5, -0.5)
        let maxBound = SIMD3<Float>(0.5, 0.5, 0.5)
        func pos(_ preset: PreviewCamera.CameraPreset) -> SIMD3<Float> {
            PreviewCamera.cameraPosition(
                minBound: minBound,
                maxBound: maxBound,
                padding: 1,
                yaw: preset.yawDegrees,
                pitch: preset.pitchDegrees,
                applyThinAxisOverride: false
            )
        }
        let back = pos(.back)
        #expect(back.z < 0)
        #expect(abs(back.x) < 0.01)
        let left = pos(.left)
        #expect(left.x < 0)
        #expect(abs(left.z) < 0.01)
        let right = pos(.right)
        #expect(right.x > 0)
        #expect(abs(right.z) < 0.01)
        let bottom = pos(.bottom)
        #expect(bottom.y < 0)
        #expect(abs(bottom.x) < 0.01)
        #expect(abs(bottom.z) < 0.01)
    }

    @MainActor
    @Test func applyFitPresetTopDoesNotTrap() {
        let preview = PerspectiveCamera()
        let bounds = BoundingBox(min: SIMD3(-0.5, -0.5, -0.5), max: SIMD3(0.5, 0.5, 0.5))
        PreviewCamera.applyFit(to: preview, bounds: bounds, aspect: 1, preset: .top)
        let eye = preview.position(relativeTo: nil)
        #expect(eye.y > 0)
        #expect(abs(eye.x) < 0.05)
        #expect(abs(eye.z) < 0.05)
        #expect(preview.components[PerspectiveCameraComponent.self] != nil)
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

    @MainActor
    @Test func applyFieldOfViewUpdatesPerspectiveOnly() throws {
        let preview = PerspectiveCamera()
        preview.camera.fieldOfViewInDegrees = PreviewCamera.defaultFieldOfViewDegrees
        PreviewCamera.applyFieldOfView(to: preview, degrees: 60)
        #expect(abs(preview.camera.fieldOfViewInDegrees - 60) < 0.001)

        PreviewCamera.applyOrthographicProjection(
            to: preview,
            bounds: BoundingBox(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        )
        PreviewCamera.applyFieldOfView(to: preview, degrees: 20)
        #expect(preview.components[PerspectiveCameraComponent.self] == nil)
        #expect(preview.components[OrthographicCameraComponent.self] != nil)
    }

    @Test func widerFieldOfViewPullsCameraCloserOnFit() {
        let minBound = SIMD3<Float>(-1, -1, -1)
        let maxBound = SIMD3<Float>(1, 1, 1)
        let narrow = PreviewCamera.cameraPosition(
            minBound: minBound,
            maxBound: maxBound,
            padding: 1,
            fieldOfViewInDegrees: 20
        )
        let wide = PreviewCamera.cameraPosition(
            minBound: minBound,
            maxBound: maxBound,
            padding: 1,
            fieldOfViewInDegrees: 70
        )
        let narrowDist = length(narrow)
        let wideDist = length(wide)
        #expect(wideDist < narrowDist)
    }

    @Test func fieldOfViewClampsToSessionRange() {
        #expect(PreviewCamera.clampedFieldOfView(5) == PreviewCamera.fieldOfViewRange.lowerBound)
        #expect(PreviewCamera.clampedFieldOfView(120) == PreviewCamera.fieldOfViewRange.upperBound)
        #expect(abs(PreviewCamera.clampedFieldOfView(35) - 35) < 0.001)
    }
}

struct OrthographicFitScaleTests {
    @Test func scaleIsAtLeastVerticalExtentTimesPadding() {
        let bounds = BoundingBox(min: SIMD3(-1, -2, -1), max: SIMD3(1, 2, 1))
        let scale = PreviewCamera.orthographicScale(bounds: bounds, aspect: 1, padding: 1.02)
        // Front 3/4 projects some height; must cover padded vertical extent at minimum.
        #expect(scale >= 4 * 1.02 - 0.01)
    }

    @Test func widerAspectRaisesScaleToFitHorizontal() {
        let bounds = BoundingBox(min: SIMD3(-4, -0.5, -0.5), max: SIMD3(4, 0.5, 0.5))
        let tall = PreviewCamera.orthographicScale(bounds: bounds, aspect: 0.5, padding: 1)
        let wide = PreviewCamera.orthographicScale(bounds: bounds, aspect: 2, padding: 1)
        // Narrow viewport (aspect 0.5) needs larger vertical scale to fit width.
        #expect(tall > wide)
    }

    @MainActor
    @Test func applyFitOrthographicSwapsProjection() throws {
        let preview = PerspectiveCamera()
        let bounds = BoundingBox(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        PreviewCamera.applyFit(to: preview, bounds: bounds, aspect: 1, orthographic: true)
        let ortho = try #require(preview.components[OrthographicCameraComponent.self])
        #expect(ortho.scale > 0)
        #expect(preview.components[PerspectiveCameraComponent.self] == nil)
    }

    @MainActor
    @Test func applyFitPerspectiveRestoresAfterOrtho() throws {
        let preview = PerspectiveCamera()
        let bounds = BoundingBox(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        PreviewCamera.applyFit(to: preview, bounds: bounds, orthographic: true)
        PreviewCamera.applyFit(to: preview, bounds: bounds, orthographic: false)
        #expect(preview.components[OrthographicCameraComponent.self] == nil)
        let perspective = try #require(preview.components[PerspectiveCameraComponent.self])
        #expect(abs(perspective.fieldOfViewInDegrees - 35) < 0.001)
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

    @MainActor
    @Test func turntablePreservesOffsetWhenCenterDisabled() {
        let root = Entity()
        root.position = SIMD3(1.5, 0, 0)
        let model = ModelEntity(mesh: .generateBox(size: 1), materials: [SimpleMaterial()])
        root.addChild(model)
        let assembled = PreviewCamera.makeTurntable(for: root, center: false)
        #expect(abs(root.position.x - 1.5) < 0.01)
        #expect(abs(root.position.y) < 0.01)
        #expect(abs(root.position.z) < 0.01)

        let gizmo = assembled.pivot.children.first { $0.name == PreviewCamera.worldOriginGizmoName }
        #expect(gizmo != nil)
        // Authored origin stays at entity local 0 → pivot-local (1.5, 0, 0) for this root.
        #expect(abs((gizmo?.position.x ?? 0) - 1.5) < 0.01)

        #expect(PreviewFloor.isHelperName(PreviewCamera.worldOriginGizmoName))
        let before = PreviewCamera.modelBounds(of: assembled.pivot, relativeTo: assembled.pivot)
        // Inflate gizmo with a huge mesh; Fit must still ignore the helper subtree.
        if let gizmo {
            gizmo.addChild(ModelEntity(mesh: .generateBox(size: 80), materials: [SimpleMaterial()]))
        }
        let after = PreviewCamera.modelBounds(of: assembled.pivot, relativeTo: assembled.pivot)
        let beforeExtent = before.max - before.min
        let afterExtent = after.max - after.min
        #expect(abs(afterExtent.x - beforeExtent.x) < 0.01)
        #expect(abs(afterExtent.y - beforeExtent.y) < 0.01)
        #expect(abs(afterExtent.z - beforeExtent.z) < 0.01)
    }

    @MainActor
    @Test func worldOriginGizmoNameIsHelper() {
        #expect(PreviewFloor.isHelperName(PreviewCamera.worldOriginGizmoName))
        #expect(!PreviewFloor.isHelperName("Cube"))
    }

    @MainActor
    @Test func previewFloorMeshDoesNotInflateModelBounds() {
        let root = Entity()
        let model = ModelEntity(mesh: .generateBox(size: 1), materials: [SimpleMaterial()])
        root.addChild(model)
        let assembled = PreviewCamera.makeTurntable(for: root)
        let before = PreviewCamera.modelBounds(of: assembled.pivot, relativeTo: assembled.pivot)

        let floor = Entity()
        floor.name = PreviewFloor.entityName
        let huge = ModelEntity(mesh: .generateBox(size: 80), materials: [SimpleMaterial()])
        floor.addChild(huge)
        assembled.pivot.addChild(floor)

        let after = PreviewCamera.modelBounds(of: assembled.pivot, relativeTo: assembled.pivot)
        let beforeExtent = before.max - before.min
        let afterExtent = after.max - after.min
        #expect(abs(afterExtent.x - beforeExtent.x) < 0.01)
        #expect(abs(afterExtent.y - beforeExtent.y) < 0.01)
        #expect(abs(afterExtent.z - beforeExtent.z) < 0.01)
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
