import Foundation
@testable import GLTFCore
import Testing

/// `GLTFDocument` read from GLB files built in memory, as the document window reads a file.
struct GLTFDocumentGLBTests {
    /// The document the window builds: original JSON plus the file for binary payloads.
    private func fileDocument(_ url: URL) throws -> GLTFDocument {
        GLTFDocumentJSON.makeDocument(json: try GLBBox.peekDocumentJSON(from: url), fileURL: url)
    }

    @Test func documentBindsMaterialsAndHonestyFields() throws {
        let url = try writeTempMixedMapsMaterialGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try fileDocument(url)
        #expect(!document.materials.isEmpty)
        let bound = document.nodes.filter { !$0.materialIndices.isEmpty }
        #expect(!bound.isEmpty)
        for node in bound {
            #expect(node.materialIndices.allSatisfy { document.materials.indices.contains($0) })
        }
        let material = try #require(document.materials.first)
        #expect(material.workflow == .metallicRoughness || material.workflow == .unlit)
        #expect([GLTFDocument.Material.AlphaMode.opaque, .mask, .blend].contains(material.alphaMode))
        #expect(!material.textures.isEmpty)
        let slot = try #require(material.textures.first)
        #expect(slot.width != nil && slot.height != nil)
        #expect(slot.thumbnailPNG != nil)
        #expect(!(slot.thumbnailPNG?.isEmpty ?? true))
    }

    @Test func documentPersistsTypedNodeFieldsFromMixedKinds() throws {
        let url = try writeTempMixedNodeKindsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try fileDocument(url)
        let byName = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.name, $0) })

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

        #expect(document.nodes.first { $0.name == "Root" }?.children.count == 5)
    }

    @Test func documentPersistsMaterialsAndMapPresence() throws {
        let url = try writeTempMixedMapsMaterialGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try fileDocument(url)
        #expect(document.materials.count == 2)

        let textured = try #require(document.materials.first { $0.name == "Textured" })
        #expect(textured.textures.map(\.kind) == [.baseColor, .normal, .metallicRoughness, .occlusion])

        let plain = try #require(document.materials.first { $0.name == "Plain" })
        #expect(plain.textures.isEmpty)
    }

    @Test func documentEnumeratesPunctualLights() throws {
        let url = try writeTempPunctualLightsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try fileDocument(url)
        #expect(document.lights.count == 3)

        let point = document.lights[0]
        #expect(point.type == "point")
        #expect(point.intensity == 5)
        #expect(point.color == SIMD3<Float>(1, 1, 1))
        #expect(point.range == nil)
        #expect(point.innerCone == nil)
        #expect(point.outerCone == nil)

        let sun = document.lights[1]
        #expect(sun.type == "directional")
        #expect(sun.intensity == 2.5)
        #expect(abs(sun.color.x - 1) < 0.0001)
        #expect(abs(sun.color.y - 1) < 0.0001)
        #expect(abs(sun.color.z - 0.9) < 0.0001)
        #expect(sun.range == nil)
        #expect(sun.innerCone == nil)

        let spot = document.lights[2]
        #expect(spot.type == "spot")
        #expect(spot.intensity == 8)
        #expect(spot.range == 12)
        #expect(spot.innerCone != nil)
        #expect(spot.outerCone != nil)
        #expect(abs((spot.innerCone ?? -1) - 0.2) < 0.0001)
        #expect(abs((spot.outerCone ?? -1) - 0.5) < 0.0001)

        #expect(document.nodes.first { $0.name == "Lamp" }?.lightIndex == 0)
        #expect(document.nodes.first { $0.name == "SunNode" }?.lightIndex == 1)
        #expect(document.nodes.first { $0.name == "SpotNode" }?.lightIndex == 2)
    }

    @Test func plainMeshHasNoDocumentLights() throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Box")
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try fileDocument(url)
        #expect(document.lights.isEmpty)
    }
}

// MARK: - Fixtures


func writeTempMixedNodeKindsGLB() throws -> URL {
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

func writeTempPunctualLightsGLB() throws -> URL {
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

func writeTempMixedMapsMaterialGLB() throws -> URL {
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
    try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "session-doc")
}
