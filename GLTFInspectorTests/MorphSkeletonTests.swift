import Foundation
import RealityKit
import Testing
@testable import GLTFInspector

struct MorphSkeletonTests {
    @MainActor
    @Test func documentPersistsMorphTargetNames() async throws {
        let model = try await loadModel(try morphTriangleGLB(), includeAnimations: false)
        #expect(model.document.morphs.count == 1)
        #expect(model.document.morphs[0].targetNames == ["Lift"])
        #expect(model.document.skins.isEmpty)
    }

    @MainActor
    @Test func morphSliderWritesBlendShapeWeights() async throws {
        let model = try await loadModel(try morphTriangleGLB(), includeAnimations: false)
        let targets = PreviewMorph.targets(in: model.entity)
        #expect(targets.count == 1)
        #expect(targets[0].name == "Lift" || targets[0].name.hasPrefix("Morph"))

        PreviewMorph.setWeight(
            nodeIndex: targets[0].nodeIndex,
            targetIndex: targets[0].targetIndex,
            value: 0.75,
            in: model.entity
        )
        let updated = PreviewMorph.targets(in: model.entity)
        #expect(abs((updated.first?.weight ?? -1) - 0.75) < 0.001)
    }

    @MainActor
    @Test func documentPersistsSkinJointNames() async throws {
        let url = try writeTempTwoJointSkinGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(model.document.skins.count == 1)
        let skin = try #require(model.document.skins.first)
        #expect(skin.jointNames.count == 2)
        #expect(skin.jointNodeIndices.count == 2)
        #expect(skin.jointParentIndices == [nil, 0])
        #expect(model.stats.isRigged)
    }

    @MainActor
    @Test func skeletonOverlayAttachesJointMarkers() async throws {
        let url = try writeTempTwoJointSkinGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        let pivot = Entity()
        pivot.name = "turntable"
        pivot.addChild(model.entity)

        PreviewSkeletonOverlay.apply(
            show: true,
            skins: model.document.skins,
            to: model.entity,
            relativeTo: pivot
        )

        let markers = jointMarkers(in: model.entity)
        #expect(markers.count == 2)
        #expect(pivot.children.contains { $0.name == PreviewSkeletonOverlay.overlayRootName })

        PreviewSkeletonOverlay.apply(
            show: false,
            skins: model.document.skins,
            to: model.entity,
            relativeTo: pivot
        )
        #expect(jointMarkers(in: model.entity).isEmpty)
        #expect(!pivot.children.contains { $0.name == PreviewSkeletonOverlay.overlayRootName })
    }

    @MainActor
    @Test func plainMeshHidesMorphAndSkinDocumentEntries() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Box")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(model.document.morphs.isEmpty)
        #expect(model.document.skins.isEmpty)
        #expect(PreviewMorph.targets(in: model.entity).isEmpty)
    }
}

@MainActor
private func jointMarkers(in root: Entity) -> [Entity] {
    var found: [Entity] = []
    func walk(_ entity: Entity) {
        if entity.name.hasPrefix(PreviewSkeletonOverlay.jointMarkerPrefix) {
            found.append(entity)
        }
        for child in entity.children {
            walk(child)
        }
    }
    walk(root)
    return found
}

/// Two named joints (parent→child) + a skinned triangle referencing the skin.
private func writeTempTwoJointSkinGLB() throws -> URL {
    var bin = floatTriangleBin()
    let positionsLength = bin.count
    // JOINTS_0: 3× UNSIGNED_SHORT VEC4 (all influence joint 0)
    for _ in 0..<3 {
        for value in [UInt16(0), 0, 0, 0] {
            var bits = value.littleEndian
            Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
        }
    }
    let jointsLength = bin.count - positionsLength
    // WEIGHTS_0: 3× FLOAT VEC4
    appendFloats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], to: &bin)
    let weightsLength = bin.count - positionsLength - jointsLength
    // IBM: two identity float4x4
    for _ in 0..<2 {
        appendFloats(
            [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            ],
            to: &bin
        )
    }
    let ibmOffset = positionsLength + jointsLength + weightsLength
    let ibmLength = bin.count - ibmOffset

    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionsLength],
            ["buffer": 0, "byteOffset": positionsLength, "byteLength": jointsLength],
            ["buffer": 0, "byteOffset": positionsLength + jointsLength, "byteLength": weightsLength],
            ["buffer": 0, "byteOffset": ibmOffset, "byteLength": ibmLength],
        ],
        "accessors": [
            [
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "max": [1, 1, 0],
                "min": [0, 0, 0],
            ],
            [
                "bufferView": 1,
                "componentType": 5123,
                "count": 3,
                "type": "VEC4",
            ],
            [
                "bufferView": 2,
                "componentType": 5126,
                "count": 3,
                "type": "VEC4",
            ],
            [
                "bufferView": 3,
                "componentType": 5126,
                "count": 2,
                "type": "MAT4",
            ],
        ],
        "meshes": [[
            "name": "SkinnedTri",
            "primitives": [[
                "attributes": [
                    "POSITION": 0,
                    "JOINTS_0": 1,
                    "WEIGHTS_0": 2,
                ],
            ]],
        ]],
        "skins": [[
            "name": "Arm",
            "joints": [1, 2],
            "inverseBindMatrices": 3,
        ]],
        "nodes": [
            ["name": "Mesh", "mesh": 0, "skin": 0, "children": [1]],
            ["name": "Hip", "children": [2], "translation": [0, 0, 0]],
            ["name": "Knee", "translation": [0, 1, 0]],
        ],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.writePrepared(try GLBBox.serialize(json: json, bin: bin), prefix: "two-joint-skin")
}

/// Morph triangle without animation (MorphConvertTests adds a weights clip).
private func morphTriangleGLB() throws -> Data {
    var bin = Data()
    appendFloats([0, 0, 0, 1, 0, 0, 0, 1, 0], to: &bin)
    let positionsLength = bin.count
    appendFloats([0, 0, 1, 0, 0, 0, 0, 0, 0], to: &bin)
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionsLength],
            ["buffer": 0, "byteOffset": positionsLength, "byteLength": bin.count - positionsLength],
        ],
        "accessors": [
            [
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [0, 0, 0],
                "max": [1, 1, 0],
            ],
            [
                "bufferView": 1,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
            ],
        ],
        "meshes": [[
            "weights": [0],
            "extras": ["targetNames": ["Lift"]],
            "primitives": [[
                "attributes": ["POSITION": 0],
                "targets": [["POSITION": 1]],
                "mode": 4,
            ]],
        ]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}
