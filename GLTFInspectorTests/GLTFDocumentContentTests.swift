import Foundation
@testable import GLTFCore
import simd
import Testing

/// `GLTFDocument` is parsed from the glTF JSON, so it describes the *file* as authored.
struct GLTFDocumentContentTests {
    @Test func documentParsesHierarchyAndTypedNodesFromJSONAlone() throws {
        let document = GLTFDocumentJSON.makeDocument(json: mixedKindsJSON())

        #expect(document.defaultSceneIndex == 0)
        #expect(document.scenes.map(\.rootNodeIndices) == [[0]])
        #expect(document.nodes.map(\.name) == ["Root", "Boxed", "Cam", "Lamp", "Hip", "Knee"])
        #expect(document.nodes[0].children == [1, 2, 3, 4])
        #expect(document.nodes[4].children == [5])

        let mesh = document.nodes[1]
        #expect(mesh.kind == .mesh)
        #expect(mesh.meshIndex == 0)
        #expect(mesh.materialIndices == [0])
        #expect(mesh.triangleCount == 1)
        #expect(mesh.vertexCount == 3)
        #expect(mesh.uvSetCount == 1)
        #expect(!mesh.hasTangents)

        #expect(document.nodes[2].kind == .camera)
        #expect(document.cameras.map(\.type) == ["perspective", "orthographic"])
        #expect(document.cameras[1].xmag == 2)
        #expect(document.nodes[3].kind == .light)
        #expect(document.lights.map(\.type) == ["spot"])
        #expect(document.lights[0].range == 12)
        #expect(abs((document.lights[0].outerCone ?? 0) - 0.5) < 0.0001)

        let skin = try #require(document.skins.first)
        #expect(skin.name == "Leg")
        #expect(skin.jointNames == ["Hip", "Knee"])
        #expect(skin.jointNodeIndices == [4, 5])

        #expect(document.morphs.map(\.targetNames) == [["Blink"]])
        #expect(document.materials[0].workflow == .metallicRoughness)
        #expect(document.materials[0].alphaMode == .mask)
        #expect(document.materials[0].alphaCutoff == 0.5)
        #expect(document.materials[0].textures.map(\.kind) == [.baseColor])
    }

    @Test func clipDurationFallsBackToTheBinaryWhenMinMaxIsMissing() {
        var times = Data()
        appendFloats([0, 1.5], to: &times)
        var single = Data()
        appendFloats([0], to: &single)
        var values = Data()
        appendFloats([0, 0, 0, 1, 0, 0], to: &values)

        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "buffers": [
                ["byteLength": times.count, "uri": dataURI(times)],
                ["byteLength": values.count, "uri": dataURI(values)],
                ["byteLength": single.count, "uri": dataURI(single)],
            ],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": times.count],
                ["buffer": 1, "byteOffset": 0, "byteLength": values.count],
                ["buffer": 2, "byteOffset": 0, "byteLength": single.count],
            ],
            "accessors": [
                // No min/max: the span has to come from the buffer bytes.
                ["bufferView": 0, "componentType": 5126, "count": 2, "type": "SCALAR"],
                ["bufferView": 1, "componentType": 5126, "count": 2, "type": "VEC3"],
                ["bufferView": 2, "componentType": 5126, "count": 1, "type": "SCALAR"],
            ],
            "animations": [
                [
                    "name": "Walk",
                    "samplers": [["input": 0, "output": 1, "interpolation": "LINEAR"]],
                    "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
                ],
                [
                    "name": "Default Take",
                    "samplers": [["input": 2, "output": 1, "interpolation": "LINEAR"]],
                    "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
                ],
            ],
            "nodes": [["name": "Root"]],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ])

        // The real clip keeps its measured duration; one-keyframe junk has none, keeping its JSON
        // index so validator pointers still line up.
        #expect(document.animations.map(\.name) == ["Walk", "Default Take"])
        #expect(abs(document.animations[0].duration - 1.5) < 0.0001)
        #expect(document.animations[1].duration == 0)
    }

    @Test func materialVariantNamesComeFromJSON() {
        let names = GLTFDocumentJSON.materialVariantNames(json: [
            "extensions": [
                "KHR_materials_variants": [
                    "variants": [["name": "Red"], ["name": ""], ["name": "Blue"]],
                ],
            ],
        ])
        #expect(names == ["Red", "Variant 1", "Blue"])
    }

    @Test func meshNodeListsEveryPrimitiveMaterialTopologyAndTris() {
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "accessors": [
                ["componentType": 5126, "count": 3, "type": "VEC3"],
                ["componentType": 5126, "count": 4, "type": "VEC3"],
            ],
            "materials": [["name": "A"], ["name": "B"]],
            "meshes": [[
                "primitives": [
                    ["attributes": ["POSITION": 0], "material": 0, "mode": 4],
                    ["attributes": ["POSITION": 1], "material": 1, "mode": 5],
                ],
            ]],
            "nodes": [["name": "Body", "mesh": 0]],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ])
        let mesh = document.nodes[0]
        #expect(mesh.meshPrimitives.count == 2)
        #expect(mesh.meshPrimitives[0].materialIndex == 0)
        #expect(mesh.meshPrimitives[0].triangleCount == 1)
        #expect(mesh.meshPrimitives[0].mode == 4)
        #expect(mesh.meshPrimitives[1].materialIndex == 1)
        #expect(mesh.meshPrimitives[1].triangleCount == 2)
        #expect(mesh.meshPrimitives[1].mode == 5)
    }

    @Test func materialUsedByListsEachNodeOnceAndSkipsUnusedMaterials() {
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "accessors": [
                ["componentType": 5126, "count": 3, "type": "VEC3"],
                ["componentType": 5126, "count": 3, "type": "VEC3"],
            ],
            "materials": [["name": "Shared"], ["name": "Lonely"]],
            "meshes": [
                ["primitives": [
                    ["attributes": ["POSITION": 0], "material": 0],
                    ["attributes": ["POSITION": 1], "material": 0],
                ]],
                ["primitives": [["attributes": ["POSITION": 0], "material": 0]]],
            ],
            "nodes": [
                ["name": "A", "mesh": 0],
                ["name": "B", "mesh": 1],
            ],
            "scenes": [["nodes": [0, 1]]],
            "scene": 0,
        ])
        #expect(document.nodeIndices(usingMaterial: 0) == [0, 1])
        #expect(document.nodeIndices(usingMaterial: 1).isEmpty)
    }

    @Test func gpuInstancingAndJointMembershipAreDerivedFromJSON() {
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "accessors": [
                ["componentType": 5126, "count": 3, "type": "VEC3"],
                ["componentType": 5126, "count": 5, "type": "VEC3"],
            ],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "skins": [["name": "Arm", "joints": [1, 2]]],
            "nodes": [
                [
                    "name": "Forest",
                    "mesh": 0,
                    "extensions": [
                        "EXT_mesh_gpu_instancing": ["attributes": ["TRANSLATION": 1]],
                    ],
                ],
                ["name": "Shoulder"],
                ["name": "Elbow"],
            ],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ])
        #expect(document.nodes[0].gpuInstanceCount == 5)
        #expect(document.nodes[1].jointOfSkinIndices == [0])
        #expect(document.nodes[2].jointOfSkinIndices == [0])
    }

    @Test func sharedPositionAccessorCountsVerticesOncePerMesh() {
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "accessors": [["componentType": 5126, "count": 12, "type": "VEC3"]],
            "meshes": [[
                "primitives": [
                    ["attributes": ["POSITION": 0]],
                    ["attributes": ["POSITION": 0]],
                ],
            ]],
            "nodes": [["mesh": 0]],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ])
        #expect(document.nodes[0].vertexCount == 12)
    }

    @Test func textureSlotsAreSizedAndThumbedFromTheFilesOwnImages() throws {
        let url = try TestGLB.writeTemp(try texturedGLB(), prefix: "texture-slots")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = GLTFDocumentJSON.makeDocument(json: try GLBBox.peekDocumentJSON(from: url), fileURL: url)
        let slot = try #require(document.materials.first?.textures.first)
        #expect(slot.kind == .baseColor)
        #expect(slot.width == 1)
        #expect(slot.height == 1)
        #expect(!(slot.thumbnailPNG?.isEmpty ?? true))
    }
}

// MARK: - Fixtures

private func dataURI(_ data: Data) -> String {
    "data:application/octet-stream;base64," + data.base64EncodedString()
}

func trianglePrimitive(material: Int?) -> [String: Any] {
    var primitive: [String: Any] = ["attributes": ["POSITION": 0]]
    if let material { primitive["material"] = material }
    return primitive
}

private func texturedGLB() throws -> Data {
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
            "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
            "max": [1, 1, 0], "min": [0, 0, 0],
        ]],
        "images": [["mimeType": "image/png", "bufferView": 1]],
        "textures": [["source": 0]],
        "materials": [[
            "name": "Painted",
            "pbrMetallicRoughness": ["baseColorTexture": ["index": 0]],
        ]],
        "meshes": [["name": "Tri", "primitives": [trianglePrimitive(material: 0)]]],
        "nodes": [["name": "Root", "mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.serialize(json: json, bin: bin)
}

/// JSON-only asset: no buffers, so nothing here can be resolved through a renderer.
private func mixedKindsJSON() -> [String: Any] {
    [
        "asset": ["version": "2.0"],
        "accessors": [
            ["componentType": 5126, "count": 3, "type": "VEC3"],
            ["componentType": 5126, "count": 3, "type": "VEC2"],
            ["componentType": 5126, "count": 3, "type": "VEC3"],
        ],
        "extensionsUsed": ["KHR_lights_punctual"],
        "extensions": [
            "KHR_lights_punctual": [
                "lights": [[
                    "name": "Spot",
                    "type": "spot",
                    "intensity": 8,
                    "range": 12,
                    "spot": ["innerConeAngle": 0.2, "outerConeAngle": 0.5],
                ]],
            ],
        ],
        "cameras": [
            ["type": "perspective", "perspective": ["yfov": 0.7, "znear": 0.1]],
            ["type": "orthographic", "orthographic": ["xmag": 2, "ymag": 2, "znear": 0.1, "zfar": 100]],
        ],
        "materials": [[
            "name": "Cutout",
            "alphaMode": "MASK",
            "pbrMetallicRoughness": ["baseColorTexture": ["index": 0]],
        ]],
        "meshes": [[
            "name": "Boxy",
            "primitives": [[
                "attributes": ["POSITION": 0, "TEXCOORD_0": 1, "NORMAL": 2],
                "material": 0,
                "targets": [["POSITION": 2]],
            ]],
            "extras": ["targetNames": ["Blink"]],
        ]],
        "skins": [["name": "Leg", "joints": [4, 5]]],
        "nodes": [
            ["name": "Root", "children": [1, 2, 3, 4]],
            ["name": "Boxed", "mesh": 0],
            ["name": "Cam", "camera": 0],
            ["name": "Lamp", "extensions": ["KHR_lights_punctual": ["light": 0]]],
            ["name": "Hip", "children": [5]],
            ["name": "Knee"],
        ],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
}
