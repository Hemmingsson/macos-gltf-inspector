import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

/// The sidebar document is parsed from the glTF JSON, so it describes the *file* rather
/// than the subset that survived RealityKit convert. These tests pin the difference.
struct SceneModelFromJSONTests {

    // MARK: - The file, not the render

    @MainActor
    @Test func ignoredExtensionStillListsWholeFile() async throws {
        let loaded = try await loadModel(try ignoredExtensionGLB(), includeAnimations: true)

        // The renderer says it dropped the extension…
        #expect(loaded.convertProblems.items.contains {
            $0.code == .ignoredExtension && $0.message.contains("KHR_materials_volume")
        })

        // …and the sidebar still describes everything the file declares.
        #expect(loaded.document.nodes.map(\.name) == ["Root", "Body", "Trim"])
        #expect(loaded.document.nodes[0].children == [1, 2])
        #expect(loaded.document.materials.map(\.name) == ["Glass", "Paint"])
        #expect(loaded.document.animations.map(\.name) == ["Spin"])
        #expect(loaded.document.scenes.map(\.rootNodeIndices) == [[0]])
    }

    @MainActor
    @Test func specGlossWorkflowSurvivesTheMetalRoughRewrite() async throws {
        // Prepare rewrites spec/gloss into metal/rough before convert; the document is built
        // from the untouched file, so the inspector reports the workflow that was authored.
        let loaded = try await loadModel(try specGlossGLB())
        let material = try #require(loaded.document.materials.first)
        #expect(material.workflow == .specularGlossiness)
        #expect(material.metallicFactor == nil)
        #expect(material.roughnessFactor == nil)
        // The rewrite really did happen — convert produced a metal/rough RealityKit material.
        #expect(!pbrMaterials(in: loaded.entity).isEmpty)
    }

    @MainActor
    @Test func gpuInstancingKeepsTheAuthoredNodeCount() async throws {
        // `RealityPrepare.expandInstances` appends four clone nodes for the renderer.
        let loaded = try await loadModel(try instancedGLB(count: 4))
        #expect(loaded.document.nodes.count == 1)
        #expect(EntityLoader.modelComponentCount(in: loaded.entity) >= 4)
    }

    // MARK: - Parsed without a renderer

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
        #expect(mesh.hasNormals)
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
        #expect(skin.jointParentIndices == [nil, 0])

        #expect(document.morphs.map(\.targetNames) == [["Blink"]])
        #expect(document.materials[0].workflow == .metallicRoughness)
        #expect(document.materials[0].alphaMode == .mask)
        #expect(document.materials[0].alphaCutoff == 0.5)
        #expect(document.materials[0].maps.baseColor)
        #expect(!document.materials[0].maps.normal)
    }

    @Test func nodeMatrixIsDecomposedIntoTRS() {
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "nodes": [[
                "name": "Matrixed",
                // Column-major: uniform scale 2, no rotation, translation (1, 2, 3).
                "matrix": [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 1, 2, 3, 1],
            ]],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ]
        let node = GLTFDocumentJSON.makeDocument(json: json).nodes[0]
        #expect(node.translation == SIMD3<Float>(1, 2, 3))
        #expect(node.scale == SIMD3<Float>(2, 2, 2))
        #expect(abs(node.rotation.real - 1) < 0.0001)
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

        // One-keyframe junk stays out; the real clip keeps its measured duration.
        #expect(document.animations.map(\.name) == ["Walk"])
        #expect(abs(document.animations[0].duration - 1.5) < 0.0001)
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

    @MainActor
    @Test func textureSlotsAreSizedAndThumbedFromTheFilesOwnImages() async throws {
        let loaded = try await loadModel(try texturedGLB())
        let slot = try #require(loaded.document.materials.first?.textures.first)
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

private func trianglePrimitive(material: Int?) -> [String: Any] {
    var primitive: [String: Any] = ["attributes": ["POSITION": 0]]
    if let material { primitive["material"] = material }
    return primitive
}

/// Triangle mesh + two materials + one clip, with two extensions RealityKit cannot render.
private func ignoredExtensionGLB() throws -> Data {
    var bin = floatTriangleBin()
    let positionLength = bin.count
    appendFloats([0, 1], to: &bin)
    let timesOffset = positionLength
    appendFloats([0, 0, 0, 1, 0, 0], to: &bin)
    let valuesOffset = timesOffset + 8

    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": ["KHR_materials_volume", "KHR_materials_transmission"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionLength],
            ["buffer": 0, "byteOffset": timesOffset, "byteLength": 8],
            ["buffer": 0, "byteOffset": valuesOffset, "byteLength": 24],
        ],
        "accessors": [
            [
                "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
                "max": [1, 1, 0], "min": [0, 0, 0],
            ],
            ["bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "max": [1], "min": [0]],
            ["bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC3"],
        ],
        "materials": [
            [
                "name": "Glass",
                "extensions": [
                    "KHR_materials_transmission": ["transmissionFactor": 1],
                    "KHR_materials_volume": ["thicknessFactor": 0.5, "attenuationDistance": 2],
                ],
            ],
            ["name": "Paint", "pbrMetallicRoughness": ["baseColorFactor": [1, 0, 0, 1]]],
        ],
        "meshes": [
            ["name": "BodyMesh", "primitives": [trianglePrimitive(material: 0)]],
            ["name": "TrimMesh", "primitives": [trianglePrimitive(material: 1)]],
        ],
        "nodes": [
            ["name": "Root", "children": [1, 2]],
            ["name": "Body", "mesh": 0],
            ["name": "Trim", "mesh": 1],
        ],
        "animations": [[
            "name": "Spin",
            "samplers": [["input": 1, "output": 2, "interpolation": "LINEAR"]],
            "channels": [["sampler": 0, "target": ["node": 1, "path": "translation"]]],
        ]],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}

private func specGlossGLB() throws -> Data {
    let bin = floatTriangleBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": ["KHR_materials_pbrSpecularGlossiness"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [[
            "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
            "max": [1, 1, 0], "min": [0, 0, 0],
        ]],
        "materials": [[
            "name": "Chrome",
            "extensions": [
                "KHR_materials_pbrSpecularGlossiness": [
                    "diffuseFactor": [0.25, 0.5, 0.75, 1],
                    "specularFactor": [1, 1, 1],
                    "glossinessFactor": 0.9,
                ],
            ],
        ]],
        "meshes": [["name": "Tri", "primitives": [trianglePrimitive(material: 0)]]],
        "nodes": [["name": "Root", "mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
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
    return try GLBBox.serialize(json: json, bin: bin)
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
