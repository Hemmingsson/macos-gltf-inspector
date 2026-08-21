import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct StillCameraPoseTests {
    @Test @MainActor func capturingPerspectiveCopiesPoseAndFOV() {
        let camera = PerspectiveCamera()
        camera.setPosition(SIMD3(1.5, 2, 3.5), relativeTo: nil)
        camera.orientation = simd_quatf(angle: .pi / 5, axis: [0, 1, 0])
        var perspective = PerspectiveCameraComponent()
        perspective.fieldOfViewInDegrees = 42
        perspective.near = 0.02
        perspective.far = 400
        camera.components.set(perspective)

        let pose = StillCameraPose.capturing(from: camera)
        #expect(pose != nil)
        guard let pose else { return }
        #expect(abs(pose.position.x - 1.5) < 1e-5)
        #expect(abs(pose.position.y - 2) < 1e-5)
        #expect(abs(pose.position.z - 3.5) < 1e-5)
        if case .perspective(let fov, let near, let far) = pose.projection {
            #expect(abs(fov - 42) < 1e-5)
            #expect(abs(near - 0.02) < 1e-5)
            #expect(abs(far - 400) < 1e-5)
        } else {
            Issue.record("expected perspective projection")
        }

        let rebuilt = pose.makeCameraEntity()
        #expect(abs(rebuilt.position(relativeTo: nil).x - 1.5) < 1e-5)
        let rebuiltPersp = rebuilt.components[PerspectiveCameraComponent.self]
        #expect(rebuiltPersp != nil)
        #expect(abs((rebuiltPersp?.fieldOfViewInDegrees ?? 0) - 42) < 1e-5)
    }

    @Test @MainActor func capturingOrthographicCopiesScale() {
        let camera = PerspectiveCamera()
        camera.setPosition(SIMD3(0, 4, 0), relativeTo: nil)
        camera.components.remove(PerspectiveCameraComponent.self)
        var orthographic = OrthographicCameraComponent()
        orthographic.scale = 2.5
        orthographic.scaleDirection = .vertical
        orthographic.near = 0.01
        orthographic.far = 100
        camera.components.set(orthographic)

        let pose = StillCameraPose.capturing(from: camera)
        #expect(pose != nil)
        guard let pose else { return }
        if case .orthographic(let scale, let near, let far) = pose.projection {
            #expect(abs(scale - 2.5) < 1e-5)
            #expect(abs(near - 0.01) < 1e-5)
            #expect(abs(far - 100) < 1e-5)
        } else {
            Issue.record("expected orthographic projection")
        }

        let rebuilt = pose.makeCameraEntity()
        #expect(rebuilt.components[OrthographicCameraComponent.self] != nil)
        #expect(rebuilt.components[PerspectiveCameraComponent.self] == nil)
    }

    @Test @MainActor func poseBasedStillRendererWritesPNG() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("scripts/testdata/cube/cube.gltf")
        try #require(FileManager.default.fileExists(atPath: url.path))

        let model = try await EntityLoader.loadThumbnail(from: url)
        let assembled = PreviewCamera.makeTurntable(for: model.entity)
        let fitCamera = PreviewCamera.makeFrontThreeQuarter(
            minBound: assembled.bounds.min,
            maxBound: assembled.bounds.max,
            padding: PreviewCamera.previewFitPadding,
            aspect: 16 / 9
        )
        // Offset from default fit so the pose path is clearly not re-deriving front-¾.
        fitCamera.setPosition(
            fitCamera.position(relativeTo: nil) + SIMD3(0.4, 0.2, 0),
            relativeTo: nil
        )
        let pose = try #require(StillCameraPose.capturing(from: fitCamera))
        let still = try await StillRenderer(
            root: assembled.pivot.clone(recursive: true),
            cameraPose: pose,
            width: 320,
            height: 180,
            background: CGColor(gray: 0.94, alpha: 1),
            intensityExponent: model.studioIBLExponent
        )
        let image = try await still.capture()
        #expect(image.width == 320)
        #expect(image.height == 180)

        let out = URL(fileURLWithPath: "/tmp/GLBPreview-pose-screenshot-proof.png")
        try StillRenderer.writePNG(image, to: out)
        let attrs = try FileManager.default.attributesOfItem(atPath: out.path)
        #expect((attrs[.size] as? NSNumber)?.intValue ?? 0 > 800)
    }
}
