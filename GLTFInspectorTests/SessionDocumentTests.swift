import Foundation
import RealityKit
import Testing
@testable import GLTFInspector

struct SessionDocumentTests {
    @MainActor
    @Test func convertStampsNodeIndexZero() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Helmet")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(stampedNodeIndices(in: model.entity).contains(0))
        #expect(model.document.nodes.contains { $0.name == "Helmet" })
        #expect(model.document.scenes.count >= 1)
        #expect(model.document.defaultSceneIndex == 0)
        #expect(model.document.scenes[model.document.defaultSceneIndex].rootNodeIndices.contains(0))
    }

    @MainActor
    @Test func convertStampsBoundMaterialAndHonestyFields() async throws {
        let url = try writeTempMixedMapsMaterialGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(!model.document.materials.isEmpty)
        let bound = model.document.nodes.filter { !$0.materialIndices.isEmpty }
        #expect(!bound.isEmpty)
        for node in bound {
            #expect(node.materialIndices.allSatisfy { model.document.materials.indices.contains($0) })
        }
        let material = try #require(model.document.materials.first)
        #expect(material.workflow == .metallicRoughness || material.workflow == .unlit)
        #expect([GLTFSessionDocument.Material.AlphaMode.opaque, .mask, .blend].contains(material.alphaMode))
    }

    @MainActor
    @Test func documentListsEverySceneFromAsset() async throws {
        let url = try writeTempTwoSceneGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(model.document.scenes.count == 2)
        #expect(model.document.defaultSceneIndex == 0)
        #expect(model.document.scenes[0].rootNodeIndices == [0])
        #expect(model.document.scenes[1].rootNodeIndices == [1])
        let stamped = stampedNodeIndices(in: model.entity)
        #expect(stamped.contains(0))
        #expect(!stamped.contains(1))
    }

    @MainActor
    @Test func lazyConvertSecondSceneStampsItsRoot() async throws {
        let twoSceneURL = try writeTempTwoSceneGLB()
        defer { try? FileManager.default.removeItem(at: twoSceneURL) }

        let other = try await EntityLoader.convertScene(
            index: 1,
            from: twoSceneURL,
            includeAnimations: true
        )
        #expect(stampedNodeIndices(in: other).contains(1))
    }

    @MainActor
    @Test func convertSceneOutOfRangeThrows1020() async throws {
        let url = try writeTempTwoSceneGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await EntityLoader.convertScene(index: 99, from: url, includeAnimations: false)
            Issue.record("expected GLTFInspectorError 1020")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == GLTFInspectorError.domain)
            #expect(nsError.code == 1020)
        }
    }

    @MainActor
    @Test func staticBoxHasNoAnimations() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Box")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        #expect(model.document.animations.isEmpty)
        #expect(model.entity.availableAnimations.isEmpty)
    }

    @MainActor
    @Test func documentAnimationsMatchUsableClips() async throws {
        let url = try writeTempTwoClipGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        #expect(model.document.animations.count == 2)
        #expect(model.document.animations.count == model.entity.availableAnimations.count)
        #expect(model.document.animations[0].name == "ClipA")
        #expect(model.document.animations[1].name == "ClipB")
        #expect(model.document.animations[0].duration > 0)
        #expect(model.document.animations[1].duration > 0)
        #expect(model.document.animations[1].duration >= model.document.animations[0].duration)

        let usable = PreviewClip.usable(on: model.entity, document: model.document)
        let listed = PreviewClip.list(from: model.document)
        #expect(usable.map(\.title) == ["ClipA", "ClipB"])
        #expect(usable.map(\.id) == listed.map(\.id))
        #expect(usable.map(\.title) == listed.map(\.title))
        #expect(usable.map(\.name) == model.document.animations.map(\.name))
    }

    @MainActor
    @Test func documentPersistsTypedNodeFieldsFromMixedKinds() async throws {
        let url = try writeTempMixedNodeKindsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        let byName = Dictionary(uniqueKeysWithValues: model.document.nodes.map { ($0.name, $0) })

        let empty = try #require(byName["Empty"])
        #expect(empty.kind == .empty)
        #expect(empty.meshIndex == nil)
        #expect(empty.cameraIndex == nil)
        #expect(empty.lightIndex == nil)
        #expect(empty.skinIndex == nil)
        #expect(empty.translation == .zero)
        #expect(empty.scale == .one)

        let mesh = try #require(byName["Mesh"])
        #expect(mesh.kind == .mesh)
        #expect(mesh.meshIndex == 0)
        #expect(mesh.translation == SIMD3<Float>(1, 2, 3))
        #expect(mesh.scale == SIMD3<Float>(2, 2, 2))
        #expect(abs(mesh.rotation.real - 1) < 0.0001)

        let cam = try #require(byName["Cam"])
        #expect(cam.kind == .camera)
        #expect(cam.cameraIndex == 0)

        let light = try #require(byName["Lamp"])
        #expect(light.kind == .light)
        #expect(light.lightIndex == 0)

        let skinned = try #require(byName["Skinned"])
        #expect(skinned.kind == .mesh)
        #expect(skinned.meshIndex == 0)
        #expect(skinned.skinIndex == 0)

        let joint = try #require(byName["Joint"])
        #expect(joint.kind == .empty)
        #expect(joint.skinIndex == nil)

        #expect(model.document.nodes.first { $0.name == "Root" }?.children.count == 5)
    }

    @MainActor
    @Test func documentPersistsMaterialsAndMapPresence() async throws {
        let url = try writeTempMixedMapsMaterialGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(model.document.materials.count == 2)

        let textured = try #require(model.document.materials.first { $0.name == "Textured" })
        #expect(textured.maps.baseColor)
        #expect(textured.maps.normal)
        #expect(textured.maps.metallicRoughness)
        #expect(textured.maps.occlusion)
        #expect(!textured.maps.emissive)

        let plain = try #require(model.document.materials.first { $0.name == "Plain" })
        #expect(!plain.maps.baseColor)
        #expect(!plain.maps.normal)
        #expect(!plain.maps.metallicRoughness)
        #expect(!plain.maps.occlusion)
        #expect(!plain.maps.emissive)
    }

    @MainActor
    @Test func documentEnumeratesPunctualLights() async throws {
        let url = try writeTempPunctualLightsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(model.document.lights.count == 3)

        let point = model.document.lights[0]
        #expect(point.type == "point")
        #expect(point.intensity == 5)
        #expect(point.color == SIMD3<Float>(1, 1, 1))
        #expect(point.range == nil)
        #expect(point.innerCone == nil)
        #expect(point.outerCone == nil)

        let sun = model.document.lights[1]
        #expect(sun.type == "directional")
        #expect(sun.intensity == 2.5)
        #expect(abs(sun.color.x - 1) < 0.0001)
        #expect(abs(sun.color.y - 1) < 0.0001)
        #expect(abs(sun.color.z - 0.9) < 0.0001)
        #expect(sun.range == nil)
        #expect(sun.innerCone == nil)

        let spot = model.document.lights[2]
        #expect(spot.type == "spot")
        #expect(spot.intensity == 8)
        #expect(spot.range == 12)
        #expect(spot.innerCone != nil)
        #expect(spot.outerCone != nil)
        #expect(abs((spot.innerCone ?? -1) - 0.2) < 0.0001)
        #expect(abs((spot.outerCone ?? -1) - 0.5) < 0.0001)

        #expect(model.document.nodes.first { $0.name == "Lamp" }?.lightIndex == 0)
        #expect(model.document.nodes.first { $0.name == "SunNode" }?.lightIndex == 1)
        #expect(model.document.nodes.first { $0.name == "SpotNode" }?.lightIndex == 2)
    }

    @MainActor
    @Test func plainMeshHasNoDocumentLights() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Box")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(model.document.lights.isEmpty)
    }
}

private func writeTempTwoSceneGLB() throws -> URL {
    let bin = floatTriangleBin()
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
        "meshes": [
            ["name": "MeshA", "primitives": [["attributes": ["POSITION": 0]]]],
            ["name": "MeshB", "primitives": [["attributes": ["POSITION": 0]]]],
        ],
        "nodes": [
            ["name": "RootA", "mesh": 0],
            ["name": "RootB", "mesh": 1],
        ],
        "scenes": [
            ["name": "SceneA", "nodes": [0]],
            ["name": "SceneB", "nodes": [1]],
        ],
        "scene": 0,
    ]
    return try writeTempGLB(json: json, bin: bin)
}

private func writeTempTwoClipGLB() throws -> URL {
    var bin = floatTriangleBin()
    let positionLength = bin.count
    appendFloats([0, 1], to: &bin)
    let timeALength = 8
    appendFloats([0, 0, 0, 1, 0, 0], to: &bin)
    let transALength = 24
    appendFloats([0, 2], to: &bin)
    let timeBLength = 8
    appendFloats([0, 0, 0, 0, 1, 0], to: &bin)
    let transBLength = 24
    let timeAOffset = positionLength
    let transAOffset = timeAOffset + timeALength
    let timeBOffset = transAOffset + transALength
    let transBOffset = timeBOffset + timeBLength
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionLength],
            ["buffer": 0, "byteOffset": timeAOffset, "byteLength": timeALength],
            ["buffer": 0, "byteOffset": transAOffset, "byteLength": transALength],
            ["buffer": 0, "byteOffset": timeBOffset, "byteLength": timeBLength],
            ["buffer": 0, "byteOffset": transBOffset, "byteLength": transBLength],
        ],
        "accessors": [
            [
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
            ],
            [
                "bufferView": 1,
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
                "min": [0.0],
                "max": [1.0],
            ],
            [
                "bufferView": 2,
                "componentType": 5126,
                "count": 2,
                "type": "VEC3",
            ],
            [
                "bufferView": 3,
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
                "min": [0.0],
                "max": [2.0],
            ],
            [
                "bufferView": 4,
                "componentType": 5126,
                "count": 2,
                "type": "VEC3",
            ],
        ],
        "meshes": [["name": "Mesh", "primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": [["name": "Root", "mesh": 0]],
        "animations": [
            [
                "name": "ClipA",
                "samplers": [["input": 1, "output": 2, "interpolation": "LINEAR"]],
                "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
            ],
            [
                "name": "ClipB",
                "samplers": [["input": 3, "output": 4, "interpolation": "LINEAR"]],
                "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
            ],
        ],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    return try writeTempGLB(json: json, bin: bin)
}

private func writeTempMixedNodeKindsGLB() throws -> URL {
    let bin = floatTriangleBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
            "max": [1, 1, 0],
            "min": [0, 0, 0],
        ]],
        "meshes": [["name": "Tri", "primitives": [["attributes": ["POSITION": 0]]]]],
        "cameras": [[
            "type": "perspective",
            "perspective": ["yfov": 0.7, "znear": 0.1],
        ]],
        "extensionsUsed": ["KHR_lights_punctual"],
        "extensions": [
            "KHR_lights_punctual": [
                "lights": [["type": "point", "intensity": 5]],
            ],
        ],
        "skins": [["joints": [5]]],
        "nodes": [
            [
                "name": "Root",
                "children": [1, 2, 3, 4, 5],
            ],
            ["name": "Empty"],
            [
                "name": "Mesh",
                "mesh": 0,
                "translation": [1, 2, 3],
                "scale": [2, 2, 2],
            ],
            ["name": "Cam", "camera": 0],
            [
                "name": "Lamp",
                "extensions": ["KHR_lights_punctual": ["light": 0]],
            ],
            ["name": "Joint"],
            [
                "name": "Skinned",
                "mesh": 0,
                "skin": 0,
            ],
        ],
        "scenes": [["name": "Default", "nodes": [0, 6]]],
        "scene": 0,
    ]
    return try writeTempGLB(json: json, bin: bin)
}

private func writeTempPunctualLightsGLB() throws -> URL {
    let bin = floatTriangleBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
            "max": [1, 1, 0],
            "min": [0, 0, 0],
        ]],
        "meshes": [["name": "Tri", "primitives": [["attributes": ["POSITION": 0]]]]],
        "extensionsUsed": ["KHR_lights_punctual"],
        "extensions": [
            "KHR_lights_punctual": [
                "lights": [
                    [
                        "name": "Lamp",
                        "type": "point",
                        "intensity": 5,
                    ],
                    [
                        "name": "Sun",
                        "type": "directional",
                        "intensity": 2.5,
                        "color": [1, 1, 0.9],
                    ],
                    [
                        "name": "Spot",
                        "type": "spot",
                        "intensity": 8,
                        "range": 12,
                        "spot": [
                            "innerConeAngle": 0.2,
                            "outerConeAngle": 0.5,
                        ],
                    ],
                ],
            ],
        ],
        "nodes": [
            ["name": "Mesh", "mesh": 0],
            [
                "name": "Lamp",
                "extensions": ["KHR_lights_punctual": ["light": 0]],
            ],
            [
                "name": "SunNode",
                "extensions": ["KHR_lights_punctual": ["light": 1]],
            ],
            [
                "name": "SpotNode",
                "extensions": ["KHR_lights_punctual": ["light": 2]],
            ],
        ],
        "scenes": [["name": "Default", "nodes": [0, 1, 2, 3]]],
        "scene": 0,
    ]
    return try writeTempGLB(json: json, bin: bin)
}

private func writeTempMixedMapsMaterialGLB() throws -> URL {
    var bin = floatTriangleBin()
    let pngStart = bin.count
    let png = tinyPNG()
    bin.append(png)
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": pngStart],
            ["buffer": 0, "byteOffset": pngStart, "byteLength": png.count],
        ],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
            "max": [1, 1, 0],
            "min": [0, 0, 0],
        ]],
        "images": [["mimeType": "image/png", "bufferView": 1]],
        "textures": [["source": 0]],
        "materials": [
            [
                "name": "Textured",
                "pbrMetallicRoughness": [
                    "baseColorTexture": ["index": 0],
                    "metallicRoughnessTexture": ["index": 0],
                ],
                "normalTexture": ["index": 0],
                "occlusionTexture": ["index": 0],
            ],
            [
                "name": "Plain",
                "pbrMetallicRoughness": [
                    "baseColorFactor": [1, 1, 1, 1],
                    "metallicFactor": 0,
                    "roughnessFactor": 1,
                ],
            ],
        ],
        "meshes": [["name": "Tri", "primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
        "nodes": [["name": "Root", "mesh": 0]],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    return try writeTempGLB(json: json, bin: bin)
}

private func writeTempGLB(json: [String: Any], bin: Data) throws -> URL {
    let data = try GLBBox.serialize(json: json, bin: bin)
    return try GLBBox.writePrepared(data, prefix: "session-doc")
}
