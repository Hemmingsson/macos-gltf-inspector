import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct SceneGraphConvertTests {
    @MainActor
    @Test func punctualLightUsesEngineUnitsAndNonZeroRange() async throws {
        let model = try await loadModel(try punctualLightsGLB())
        #expect(EntityLoader.punctualLightCount(in: model.entity) == 2)

        let point = try #require(firstComponent(PointLightComponent.self, in: model.entity))
        #expect(abs(point.intensity - 10 * 4 * .pi) < 0.01)
        #expect(point.attenuationRadius > 0)
        #expect(abs(point.attenuationRadius - 1_000_000) < 1)

        let directional = try #require(firstComponent(DirectionalLightComponent.self, in: model.entity))
        #expect(abs(directional.intensity - 2.5) < 0.01)
    }

    @MainActor
    @Test func twoPerspectiveCamerasStayListedAfterTurntable() async throws {
        let model = try await loadModel(try twoPerspectiveCamerasGLB())
        #expect(model.document.cameras.count == 2)
        #expect(model.document.cameras.allSatisfy { $0.type == "perspective" })
        #expect(model.document.nodes.contains { $0.name == "CamA" && $0.cameraIndex != nil })
        #expect(model.document.nodes.contains { $0.name == "CamB" && $0.cameraIndex != nil })

        let assembled = PreviewCamera.makeTurntable(for: model.entity)
        #expect(assembled.pivot.name == "turntable")
        #expect(namedEntity("CamA", in: assembled.pivot) != nil)
        #expect(namedEntity("CamB", in: assembled.pivot) != nil)
        #expect(livePerspectiveCount(in: assembled.pivot) == 0)
    }

    @MainActor
    @Test func twoPositiveClipsKeptAndOneKeyframeDropped() async throws {
        let model = try await loadModel(try threeClipTriangleGLB(), includeAnimations: true)
        #expect(model.stats.animationCount == 2)
        #expect(model.document.animations.count == 2)
    }

    @MainActor
    @Test func thumbnailKeepsPunctualPBRAndStudioLighting() async throws {
        let model = try await loadModel(try litMetallicTriangleGLB())
        let material = try #require(pbrMaterials(in: model.entity).first)
        #expect(abs(material.metallic.scale - 1) < 0.001)
        #expect(abs(material.roughness.scale - 0.2) < 0.001)
        #expect(EntityLoader.punctualLightCount(in: model.entity) == 1)

        await PreviewLighting.prefetchLook(.current)
        let renderer = try RealityRenderer()
        await PreviewLighting.configureThumbnailLighting(on: renderer)
        #expect(renderer.lighting.resource != nil)
    }

    @MainActor
    @Test func orthographicCameraConverts() async throws {
        let model = try await loadModel(try orthographicCameraGLB())
        #expect(model.document.cameras.contains { $0.type == "orthographic" })
        #expect(model.document.nodes.contains { $0.name == "OrthoCam" && $0.cameraIndex != nil })
        let node = try #require(firstComponent(OrthographicCameraComponent.self, in: model.entity))
        #expect(node.scale > 0)
    }
}

@MainActor
private func livePerspectiveCount(in entity: Entity) -> Int {
    var count = entity.components[PerspectiveCameraComponent.self] != nil ? 1 : 0
    for child in entity.children {
        count += livePerspectiveCount(in: child)
    }
    return count
}

private func triangleMeshJSON(material: [String: Any]?, extraNodes: [[String: Any]], extraRootNodes: [Int]) -> [String: Any] {
    var meshPrimitive: [String: Any] = ["attributes": ["POSITION": 0]]
    var materials: [[String: Any]] = []
    if let material {
        meshPrimitive["material"] = 0
        materials = [material]
    }
    var nodes: [[String: Any]] = [["mesh": 0, "name": "Mesh"]]
    nodes.append(contentsOf: extraNodes)
    var rootNodes = [0]
    rootNodes.append(contentsOf: extraRootNodes)
    var json: [String: Any] = [
        "asset": ["version": "2.0"],
        "meshes": [["primitives": [meshPrimitive]]],
        "nodes": nodes,
        "scenes": [["nodes": rootNodes]],
        "scene": 0,
    ]
    if !materials.isEmpty {
        json["materials"] = materials
    }
    return json
}

private func punctualLightsGLB() throws -> Data {
    var bin = Data()
    appendFloats(floatTrianglePositions(), to: &bin)
    var json = triangleMeshJSON(
        material: nil,
        extraNodes: [[
            "name": "Sun",
            "extensions": ["KHR_lights_punctual": ["light": 1]],
        ]],
        extraRootNodes: [1]
    )
    var nodes = json["nodes"] as! [[String: Any]]
    nodes[0]["extensions"] = ["KHR_lights_punctual": ["light": 0]]
    json["nodes"] = nodes
    json["extensionsUsed"] = ["KHR_lights_punctual"]
    json["extensions"] = [
        "KHR_lights_punctual": [
            "lights": [
                ["type": "point", "intensity": 10, "range": 0],
                ["type": "directional", "intensity": 2.5],
            ],
        ],
    ]
    json["buffers"] = [["byteLength": bin.count]]
    json["bufferViews"] = [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]]
    json["accessors"] = [[
        "bufferView": 0,
        "componentType": 5126,
        "count": 3,
        "type": "VEC3",
        "max": [1, 1, 0],
        "min": [0, 0, 0],
    ]]
    return try GLBBox.serialize(json: json, bin: bin)
}

private func twoPerspectiveCamerasGLB() throws -> Data {
    var bin = Data()
    appendFloats(floatTrianglePositions(), to: &bin)
    var json = triangleMeshJSON(
        material: nil,
        extraNodes: [
            ["name": "CamA", "camera": 0],
            ["name": "CamB", "camera": 1],
        ],
        extraRootNodes: [1, 2]
    )
    json["cameras"] = [
        [
            "type": "perspective",
            "perspective": ["yfov": 0.7, "znear": 0.1, "zfar": 100],
        ],
        [
            "type": "perspective",
            "perspective": ["yfov": 0.5, "znear": 0.1, "zfar": 100],
        ],
    ]
    json["buffers"] = [["byteLength": bin.count]]
    json["bufferViews"] = [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]]
    json["accessors"] = [[
        "bufferView": 0,
        "componentType": 5126,
        "count": 3,
        "type": "VEC3",
        "max": [1, 1, 0],
        "min": [0, 0, 0],
    ]]
    return try GLBBox.serialize(json: json, bin: bin)
}

private func orthographicCameraGLB() throws -> Data {
    var bin = Data()
    appendFloats(floatTrianglePositions(), to: &bin)
    var json = triangleMeshJSON(
        material: nil,
        extraNodes: [["name": "OrthoCam", "camera": 0]],
        extraRootNodes: [1]
    )
    json["cameras"] = [[
        "type": "orthographic",
        "orthographic": ["xmag": 1, "ymag": 1, "znear": 0.1, "zfar": 100],
    ]]
    json["buffers"] = [["byteLength": bin.count]]
    json["bufferViews"] = [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]]
    json["accessors"] = [[
        "bufferView": 0,
        "componentType": 5126,
        "count": 3,
        "type": "VEC3",
        "max": [1, 1, 0],
        "min": [0, 0, 0],
    ]]
    return try GLBBox.serialize(json: json, bin: bin)
}

private func litMetallicTriangleGLB() throws -> Data {
    var bin = Data()
    appendFloats(floatTrianglePositions(), to: &bin)
    var json = triangleMeshJSON(
        material: [
            "pbrMetallicRoughness": [
                "baseColorFactor": [0.7, 0.7, 0.7, 1],
                "metallicFactor": 1,
                "roughnessFactor": 0.2,
            ],
        ],
        extraNodes: [],
        extraRootNodes: []
    )
    var nodes = json["nodes"] as! [[String: Any]]
    nodes[0]["extensions"] = ["KHR_lights_punctual": ["light": 0]]
    json["nodes"] = nodes
    json["extensionsUsed"] = ["KHR_lights_punctual"]
    json["extensions"] = [
        "KHR_lights_punctual": [
            "lights": [
                ["type": "point", "intensity": 5, "range": 10],
            ],
        ],
    ]
    json["buffers"] = [["byteLength": bin.count]]
    json["bufferViews"] = [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]]
    json["accessors"] = [[
        "bufferView": 0,
        "componentType": 5126,
        "count": 3,
        "type": "VEC3",
        "max": [1, 1, 0],
        "min": [0, 0, 0],
    ]]
    return try GLBBox.serialize(json: json, bin: bin)
}

private func threeClipTriangleGLB() throws -> Data {
    var bin = Data()
    appendFloats(floatTrianglePositions(), to: &bin)
    let positionsLength = bin.count
    appendFloats([0, 1], to: &bin)
    let timesAOffset = positionsLength
    let timesALength = 8
    appendFloats([0, 0, 0, 0, 1, 0], to: &bin)
    let transAOffset = timesAOffset + timesALength
    let transALength = 24
    appendFloats([0, 2], to: &bin)
    let timesBOffset = transAOffset + transALength
    let timesBLength = 8
    appendFloats([0, 0, 0, 1, 0, 0], to: &bin)
    let transBOffset = timesBOffset + timesBLength
    let transBLength = 24
    appendFloats([0], to: &bin)
    let timesCOffset = transBOffset + transBLength
    let timesCLength = 4
    appendFloats([0, 0, 0], to: &bin)
    let transCOffset = timesCOffset + timesCLength
    let transCLength = 12

    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionsLength],
            ["buffer": 0, "byteOffset": timesAOffset, "byteLength": timesALength],
            ["buffer": 0, "byteOffset": transAOffset, "byteLength": transALength],
            ["buffer": 0, "byteOffset": timesBOffset, "byteLength": timesBLength],
            ["buffer": 0, "byteOffset": transBOffset, "byteLength": transBLength],
            ["buffer": 0, "byteOffset": timesCOffset, "byteLength": timesCLength],
            ["buffer": 0, "byteOffset": transCOffset, "byteLength": transCLength],
        ],
        "accessors": [
            [
                "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
                "max": [1, 1, 0], "min": [0, 0, 0],
            ],
            [
                "bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR",
                "max": [1], "min": [0],
            ],
            [
                "bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC3",
                "max": [0, 1, 0], "min": [0, 0, 0],
            ],
            [
                "bufferView": 3, "componentType": 5126, "count": 2, "type": "SCALAR",
                "max": [2], "min": [0],
            ],
            [
                "bufferView": 4, "componentType": 5126, "count": 2, "type": "VEC3",
                "max": [1, 0, 0], "min": [0, 0, 0],
            ],
            [
                "bufferView": 5, "componentType": 5126, "count": 1, "type": "SCALAR",
                "max": [0], "min": [0],
            ],
            [
                "bufferView": 6, "componentType": 5126, "count": 1, "type": "VEC3",
                "max": [0, 0, 0], "min": [0, 0, 0],
            ],
        ],
        "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": [["mesh": 0, "name": "Mesh"]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
        "animations": [
            [
                "name": "clipA",
                "samplers": [["input": 1, "interpolation": "LINEAR", "output": 2]],
                "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
            ],
            [
                "name": "clipB",
                "samplers": [["input": 3, "interpolation": "LINEAR", "output": 4]],
                "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
            ],
            [
                "name": "Default Take",
                "samplers": [["input": 5, "interpolation": "LINEAR", "output": 6]],
                "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
            ],
        ],
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}
