import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct ViewerSessionTests {
    @Test func intensityExponentMapsSliderOntoDefault() {
        let session = ViewerSession(document: GLTFSessionDocument(), defaultExponent: 0)
        #expect(session.intensityExponent(forSlider: 1) == 0)
        #expect(session.intensityExponent(forSlider: 2) == 1)

        let dimmed = ViewerSession(document: GLTFSessionDocument(), defaultExponent: -2)
        #expect(dimmed.intensityExponent(forSlider: 1) == -2)
        #expect(dimmed.intensityExponent(forSlider: 0) == -2 + log2(Float(0.01)))
    }

    @MainActor
    @Test func iblOffRemovesReceivers() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Mesh")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await GLBEntityLoader.load(from: url, includeAnimations: false)
        let session = ViewerSession(
            document: model.document,
            defaultExponent: hasPunctualLight(model.entity) ? -2 : 0
        )
        let ibl = makeDummyIBLEntity()
        session.apply(root: model.entity, iblEntity: ibl)
        #expect(model.entity.components[ImageBasedLightReceiverComponent.self] != nil)

        session.imageBased = false
        session.apply(root: model.entity, iblEntity: ibl)
        #expect(model.entity.components[ImageBasedLightReceiverComponent.self] == nil)
    }

    @MainActor
    @Test func applySetsIBLIntensityAndYaw() {
        let root = Entity()
        let ibl = makeDummyIBLEntity()
        let session = ViewerSession(document: GLTFSessionDocument(), defaultExponent: 0)
        session.iblIntensity = 2
        session.environmentRotation = .minusZ
        session.apply(root: root, iblEntity: ibl)

        #expect(ibl.components[ImageBasedLightComponent.self]?.intensityExponent == 1)
        let expected = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        #expect(dot(ibl.orientation, expected) > 0.999)
    }

    @MainActor
    @Test func punctualOffDisablesLights() {
        let root = Entity()
        let light = Entity()
        light.components.set(PointLightComponent())
        root.addChild(light)

        let session = ViewerSession(document: GLTFSessionDocument(), defaultExponent: -2)
        session.punctualLights = false
        session.apply(root: root, iblEntity: nil)
        #expect(firstLightEnabled(root) == false)

        session.punctualLights = true
        session.apply(root: root, iblEntity: nil)
        #expect(firstLightEnabled(root) == true)
    }

    @Test func layerRowsFollowActiveSceneRoots() {
        var doc = GLTFSessionDocument()
        doc.scenes = [
            .init(name: "A", rootNodeIndices: [0]),
            .init(name: "B", rootNodeIndices: [1]),
        ]
        doc.nodes = [
            .init(
                index: 0,
                name: "RootA",
                children: [],
                meshIndex: 0,
                cameraIndex: nil,
                lightIndex: nil,
                translation: .zero,
                rotation: SIMD4<Float>(0, 0, 0, 1),
                scale: .one
            ),
            .init(
                index: 1,
                name: "RootB",
                children: [],
                meshIndex: 1,
                cameraIndex: nil,
                lightIndex: nil,
                translation: .zero,
                rotation: SIMD4<Float>(0, 0, 0, 1),
                scale: .one
            ),
        ]
        let session = ViewerSession(document: doc, defaultExponent: 0)
        session.activeSceneIndex = 0
        #expect(session.layerRootIndices() == [0])
        session.activeSceneIndex = 1
        #expect(session.layerRootIndices() == [1])
    }

    @Test func catalogDefaultIsStudioNeutral() {
        let s = ViewerSession(document: .init(), defaultExponent: 0)
        #expect(s.environment == .studioNeutral)
        #expect(s.showEnvironmentMap == false)
        #expect(s.blurEnvironment == false)
        #expect(s.userHDRs.isEmpty)
        #expect(s.inspectorError == nil)
        #expect(s.exposure == 1)
        #expect(s.toneMap == .khronosPBRNeutral)
        #expect(ViewerSession.ToneMap.allCases.map(\.title) == [
            "Khronos PBR Neutral",
            "ACES Filmic Tone Mapping (Hill - Exposure Boost)",
            "ACES Filmic Tone Mapping (Narkowicz)",
            "ACES Filmic Tone Mapping (Hill)",
            "None (Linear mapping, clamped at 1.0)",
        ])
    }

    @Test func selectedCameraIndexDefaultsToFit() {
        var doc = GLTFSessionDocument()
        doc.cameras = [
            .init(name: "Front", type: "perspective", yfov: 0.7, znear: 0.1, zfar: 100, xmag: nil, ymag: nil),
        ]
        let session = ViewerSession(document: doc, defaultExponent: 0)
        #expect(session.selectedCameraIndex == nil)
        session.selectedCameraIndex = 0
        #expect(session.selectedCameraIndex == 0)
    }

    @Test func selectingAnimationUpdatesSelection() {
        var doc = GLTFSessionDocument()
        doc.animations = [
            .init(name: "ClipA", duration: 1),
            .init(name: "ClipB", duration: 2),
        ]
        let session = ViewerSession(document: doc, defaultExponent: 0)
        #expect(session.selected == .none)
        #expect(session.enabledClipIndices == [0, 1])
        session.selected = .animation(1)
        #expect(session.selected == .animation(1))
        if case .animation(let index) = session.selected {
            #expect(session.document.animations[index].name == "ClipB")
            #expect(session.document.animations[index].duration == 2)
        }
    }

    @MainActor
    @Test func hideDisablesMappedEntity() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Mesh")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await GLBEntityLoader.load(from: url, includeAnimations: false)
        let session = ViewerSession(document: model.document, defaultExponent: 0)
        session.hide.insert(0)
        session.apply(root: model.entity, iblEntity: nil)
        #expect(entity(nodeIndex: 0, in: model.entity)?.isEnabled == false)
    }

    @Test func showAllClearsHide() {
        let session = ViewerSession(document: .init(), defaultExponent: 0)
        session.hide = [0, 1]
        session.soloRoot = 0
        session.showAll()
        #expect(session.hide.isEmpty)
        #expect(session.soloRoot == nil)
    }
}

private func makeDummyIBLEntity() -> Entity {
    let ibl = Entity()
    ibl.components.set(ImageBasedLightComponent(source: .none, intensityExponent: 0))
    return ibl
}

private func hasPunctualLight(_ entity: Entity) -> Bool {
    if entity.components.has(PointLightComponent.self)
        || entity.components.has(SpotLightComponent.self)
        || entity.components.has(DirectionalLightComponent.self)
    {
        return true
    }
    return entity.children.contains { hasPunctualLight($0) }
}

private func entity(nodeIndex: Int, in root: Entity) -> Entity? {
    if root.components[GLTFNodeIDComponent.self]?.nodeIndex == nodeIndex {
        return root
    }
    for child in root.children {
        if let found = entity(nodeIndex: nodeIndex, in: child) {
            return found
        }
    }
    return nil
}

private func firstLightEnabled(_ entity: Entity) -> Bool? {
    if entity.components.has(PointLightComponent.self)
        || entity.components.has(SpotLightComponent.self)
        || entity.components.has(DirectionalLightComponent.self)
    {
        return entity.isEnabled
    }
    for child in entity.children {
        if let enabled = firstLightEnabled(child) {
            return enabled
        }
    }
    return nil
}

private func triangleBin() -> Data {
    var bin = Data()
    for value: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    return bin
}

private func writeTempOneNodeMeshGLB(nodeName: String) throws -> URL {
    let bin = triangleBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
        ]],
        "meshes": [["name": "HelmetMesh", "primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": [["name": nodeName, "mesh": 0]],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    let data = try GLBBox.serialize(json: json, bin: bin)
    return try GLBBox.writePrepared(data, prefix: "viewer-session")
}
