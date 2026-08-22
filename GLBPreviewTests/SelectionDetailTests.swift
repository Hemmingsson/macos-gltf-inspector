import Foundation
import Testing
import simd
@testable import GLBPreview

struct SelectionDetailTests {
    @Test func meshShowsGeometryAndMaterialChipsNotCameraOrLight() throws {
        var doc = GLTFSessionDocument()
        doc.nodes = [
            .init(
                index: 0,
                name: "Body",
                children: [],
                kind: .mesh,
                translation: SIMD3(0.42, 0.71, -0.10),
                rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                scale: .one,
                meshIndex: 0,
                cameraIndex: nil,
                lightIndex: nil,
                skinIndex: 1,
                materialIndices: [0]
            ),
        ]
        doc.materials = [
            .init(name: "Duck_Mat", maps: MaterialMapPresence(baseColor: true, normal: true)),
            .init(name: "Plain", maps: MaterialMapPresence()),
        ]
        doc.cameras = [
            .init(name: "Cam", type: "perspective", yfov: 1, znear: 0.1, zfar: 100, xmag: nil, ymag: nil),
        ]
        doc.lights = [
            .init(name: "Lamp", type: "point", color: .one, intensity: 1, range: nil, innerCone: nil, outerCone: nil),
        ]

        let detail = try #require(SelectionDetail.resolve(nodeIndex: 0, in: doc))
        #expect(detail.kind == .mesh)
        #expect(detail.kindLabel == "Mesh")
        #expect(detail.geometryChips == ["Mesh 0", "Skin 1"])
        #expect(detail.materials.map(\.name) == ["Duck_Mat"])
        #expect(detail.materials[0].maps == ["Base Color", "Normal"])
        #expect(detail.camera == nil)
        #expect(detail.light == nil)
        #expect(abs(detail.translation.x - 0.42) < 0.0001)
        #expect(abs(detail.scale.y - 1) < 0.0001)
    }

    @Test func cameraShowsProjectionFieldsNotGeometryOrMaterials() throws {
        var doc = GLTFSessionDocument()
        doc.nodes = [
            .init(
                index: 2,
                name: "Cam",
                children: [],
                kind: .camera,
                translation: .zero,
                rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                scale: .one,
                meshIndex: nil,
                cameraIndex: 0,
                lightIndex: nil,
                skinIndex: nil
            ),
        ]
        doc.cameras = [
            .init(
                name: "Main",
                type: "perspective",
                yfov: .pi / 2,
                znear: 0.05,
                zfar: 50,
                xmag: nil,
                ymag: nil
            ),
        ]
        doc.materials = [
            .init(name: "Unused", maps: MaterialMapPresence(baseColor: true)),
        ]

        let detail = try #require(SelectionDetail.resolve(nodeIndex: 2, in: doc))
        #expect(detail.kind == .camera)
        #expect(detail.geometryChips.isEmpty)
        #expect(detail.materials.isEmpty)
        #expect(detail.light == nil)
        let camera = try #require(detail.camera)
        #expect(camera.type == "perspective")
        #expect(abs((camera.yfovDegrees ?? -1) - 90) < 0.01)
        #expect(abs(camera.znear - 0.05) < 0.0001)
        #expect(camera.zfar == 50)
    }

    @Test func lightShowsPunctualFieldsNotMaterials() throws {
        var doc = GLTFSessionDocument()
        doc.nodes = [
            .init(
                index: 3,
                name: "SpotNode",
                children: [],
                kind: .light,
                translation: SIMD3(1, 2, 3),
                rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                scale: .one,
                meshIndex: nil,
                cameraIndex: nil,
                lightIndex: 0,
                skinIndex: nil
            ),
        ]
        doc.lights = [
            .init(
                name: "Spot",
                type: "spot",
                color: SIMD3(1, 0.5, 0.25),
                intensity: 8,
                range: 12,
                innerCone: 0.2,
                outerCone: 0.5
            ),
        ]
        doc.materials = [
            .init(name: "Unused", maps: MaterialMapPresence(emissive: true)),
        ]

        let detail = try #require(SelectionDetail.resolve(nodeIndex: 3, in: doc))
        #expect(detail.kind == .light)
        #expect(detail.geometryChips.isEmpty)
        #expect(detail.materials.isEmpty)
        #expect(detail.camera == nil)
        let light = try #require(detail.light)
        #expect(light.type == "spot")
        #expect(abs(light.intensity - 8) < 0.0001)
        #expect(light.range == 12)
        #expect(abs((light.innerConeDegrees ?? -1) - (0.2 * 180 / .pi)) < 0.01)
        #expect(abs((light.outerConeDegrees ?? -1) - (0.5 * 180 / .pi)) < 0.01)
    }

    @Test func missingNodeReturnsNil() {
        #expect(SelectionDetail.resolve(nodeIndex: 9, in: GLTFSessionDocument()) == nil)
    }
}
