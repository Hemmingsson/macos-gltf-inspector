import Foundation
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

struct PreviewFloorTests {

    @MainActor
    @Test func makeBuildsNamedFloorWithMeshParts() {
        let bounds = BoundingBox(min: SIMD3(-1, 0, -1), max: SIMD3(1, 2, 1))
        let floor = PreviewFloor.make(bounds: bounds)
        #expect(floor.name == PreviewFloor.entityName)
        #expect(abs(floor.position.y - (bounds.min.y - PreviewFloor.yBias)) < 0.0001)

        var meshParts = 0
        func walk(_ node: Entity) {
            if node.components[ModelComponent.self] != nil {
                meshParts += 1
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(floor)

        let expected =
            PreviewFloor.ringCount
            + PreviewFloor.radialCount
        #expect(meshParts == expected)
    }
}

@MainActor
struct PreviewInteractionTests {
    @Test func markFittedClearsPause() {
        let interaction = PreviewInteraction()
        interaction.noteOrbitDrag()
        #expect(interaction.isCameraGesturing)
        interaction.markFitted()
        #expect(!interaction.isCameraGesturing)
    }

    @Test func markFittedKeepsSessionFieldOfView() throws {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60
        let interaction = PreviewInteraction()
        interaction.bind(camera: camera, orbitFocus: Entity())
        interaction.markFitted()
        #expect(abs(camera.camera.fieldOfViewInDegrees - 60) < 0.001)
    }

    @Test func pointerUpResumesImmediately() {
        let interaction = PreviewInteraction()
        interaction.noteOrbitDrag()
        #expect(interaction.isCameraGesturing)
        interaction.notePointerUp()
        #expect(!interaction.isCameraGesturing)
    }

    @Test func floorHasNoDiscOnlyLineMeshes() {
        let bounds = BoundingBox(min: SIMD3(-1, 0, -1), max: SIMD3(1, 2, 1))
        let floor = PreviewFloor.make(bounds: bounds)
        var names: [String] = []
        func walk(_ node: Entity) {
            names.append(node.name)
            for child in node.children { walk(child) }
        }
        walk(floor)
        #expect(!names.contains("shadowCatcher"))
        #expect(names.contains("polarGrid"))
        #expect(names.contains("polarRing1"))
    }

    @Test func gridLineColorTracksBackdrop() {
        let light = PreviewBackground.white.gridLineNSColor(systemDark: false)
        let dark = PreviewBackground.dark.gridLineNSColor(systemDark: true)
        #expect(light.brightnessComponent < dark.brightnessComponent)
    }
}
