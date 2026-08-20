import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

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
        #expect(interaction.suppressesAutoRotate)
        interaction.markFitted()
        #expect(!interaction.suppressesAutoRotate)
        #expect(!interaction.isCameraGesturing)
    }

    @Test func pointerUpResumesImmediately() {
        let interaction = PreviewInteraction()
        interaction.noteOrbitDrag()
        #expect(interaction.suppressesAutoRotate)
        interaction.notePointerUp()
        #expect(!interaction.suppressesAutoRotate)
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
