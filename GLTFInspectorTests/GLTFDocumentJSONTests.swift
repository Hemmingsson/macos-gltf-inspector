import Foundation
@testable import GLTFCore
import simd
import Testing

/// Pins `GLTFDocumentJSON.makeDocument` output: JSONSerialization `NSNumber` graphs must
/// match Swift-literal graphs, and the instance-matrix / multi-skin paths must stay exact.
struct GLTFDocumentJSONTests {
    @Test func jsonSerializationRoundTripMatchesLiteralDocument() throws {
        let literal = roundTripJSON()
        let data = try JSONSerialization.data(withJSONObject: literal)
        let parsed = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(GLTFDocumentJSON.makeDocument(json: literal) == GLTFDocumentJSON.makeDocument(json: parsed))
    }

    @Test func matrixClassesDecomposeTheSameAsTRS() {
        let translationOnly: [Double] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            4, 5, 6, 1,
        ]
        let positiveDiagonal: [Double] = [
            2, 0, 0, 0,
            0, 3, 0, 0,
            0, 0, 4, 0,
            1, 2, 3, 1,
        ]
        let negativeX: [Double] = [
            -2, 0, 0, 0,
            0, 3, 0, 0,
            0, 0, 4, 0,
            0, 0, 0, 1,
        ]
        let twoAxisNegative: [Double] = [
            -1, 0, 0, 0,
            0, -1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]
        let rotated: [Double] = [
            53.0964, 0, 0, 0,
            0, -31.2167, -42.9505, 0,
            0, 42.9505, -31.2167, 0,
            0, 5.73115, -69.3003, 1,
        ]

        let nodes: [[String: Any]] = [
            ["name": "T", "matrix": translationOnly],
            ["name": "S", "matrix": positiveDiagonal],
            ["name": "NX", "matrix": negativeX],
            ["name": "NN", "matrix": twoAxisNegative],
            ["name": "R", "matrix": rotated],
            ["name": "Bad", "matrix": [1, 2, 3], "translation": [9, 8, 7], "scale": [2, 2, 2]],
        ]
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "nodes": nodes,
            "scenes": [["nodes": Array(0..<nodes.count)]],
            "scene": 0,
        ])
        let byName = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.name, $0) })

        let translated = byName["T"]!
        #expect(translated.translation == SIMD3<Float>(4, 5, 6))
        #expect(translated.scale == SIMD3<Float>(1, 1, 1))
        #expect(abs(translated.rotation.real - 1) < 0.0001)

        let scaled = byName["S"]!
        #expect(scaled.translation == SIMD3<Float>(1, 2, 3))
        #expect(scaled.scale == SIMD3<Float>(2, 3, 4))
        #expect(abs(scaled.rotation.real - 1) < 0.0001)

        let flipped = byName["NX"]!
        #expect(flipped.scale == SIMD3<Float>(-2, 3, 4))
        #expect(abs(flipped.rotation.real - 1) < 0.0001)

        let twiceFlipped = byName["NN"]!
        #expect(twiceFlipped.scale == SIMD3<Float>(1, 1, 1))
        #expect(abs(twiceFlipped.rotation.imag.z) > 0.9)
        #expect(abs(twiceFlipped.rotation.real) < 0.0001)

        let spun = byName["R"]!
        #expect(spun.translation == SIMD3<Float>(0, 5.73115, -69.3003))
        #expect(abs(spun.scale.x - 53.0964) < 0.001)
        #expect(abs(spun.scale.y - 53.0964) < 0.02)
        #expect(abs(spun.scale.z - 53.0964) < 0.02)

        let fallback = byName["Bad"]!
        #expect(fallback.translation == SIMD3<Float>(9, 8, 7))
        #expect(fallback.scale == SIMD3<Float>(2, 2, 2))
    }

    @Test func twoSkinsShareOneParentForest() {
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "skins": [
                ["name": "Full", "joints": [0, 1, 2]],
                ["name": "Tip", "joints": [1, 2]],
            ],
            "nodes": [
                ["name": "Root", "children": [1]],
                ["name": "Mid", "children": [2]],
                ["name": "Leaf"],
            ],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ])
        #expect(document.skins.map(\.name) == ["Full", "Tip"])
        #expect(document.skins[0].jointParentIndices == [nil, 0, 1])
        #expect(document.skins[1].jointParentIndices == [nil, 0])
        #expect(document.skins[1].jointNodeIndices == [1, 2])
    }

    @Test func instanceForestIsDeterministicAndRoundTripsJSON() throws {
        let literal = instanceForestJSON(count: 64)
        let first = GLTFDocumentJSON.makeDocument(json: literal)
        let second = GLTFDocumentJSON.makeDocument(json: literal)
        #expect(first == second)
        #expect(first.nodes.count == 64)
        #expect(first.nodes[0].children.count == 63)
        #expect(first.nodes[4].translation == SIMD3<Float>(4, 0, 0))
        #expect(first.nodes[4].scale == SIMD3<Float>(1, 1, 1))
        #expect(first.nodes[1].scale == SIMD3<Float>(2, 3, 4))
        #expect(first.nodes[2].scale == SIMD3<Float>(-2, 3, 4))

        let data = try JSONSerialization.data(withJSONObject: literal)
        let parsed = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(GLTFDocumentJSON.makeDocument(json: parsed) == first)
    }

    @Test func texturePreviewMatchesStandaloneImageIOHelpers() throws {
        let url = try TestGLB.writeTemp(try texturedPreviewGLB(), prefix: "doc-preview")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = GLTFDocumentJSON.makeDocument(
            json: try GLBBox.peekDocumentJSON(from: url),
            fileURL: url
        )
        let slot = try #require(document.materials.first?.textures.first)
        let png = tinyPNG()
        #expect(slot.width == GLTFImageDecode.pixelSize(of: png)?.width)
        #expect(slot.height == GLTFImageDecode.pixelSize(of: png)?.height)
        #expect(slot.thumbnailPNG == GLTFImageDecode.thumbnailPNG(from: png, maxEdge: 96))
    }
}

private func roundTripJSON() -> [String: Any] {
    [
        "asset": ["version": "2.0"],
        "accessors": [
            ["componentType": 5126, "count": 3, "type": "VEC3"],
            ["componentType": 5126, "count": 2, "type": "SCALAR", "min": [0.0], "max": [1.5]],
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
        ],
        "materials": [[
            "name": "Cutout",
            "alphaMode": "MASK",
            "pbrMetallicRoughness": ["baseColorTexture": ["index": 0]],
        ]],
        "meshes": [[
            "name": "Boxy",
            "primitives": [[
                "attributes": ["POSITION": 0, "TEXCOORD_0": 0, "NORMAL": 0],
                "material": 0,
                "targets": [["POSITION": 0]],
            ]],
            "extras": ["targetNames": ["Blink"]],
        ]],
        "skins": [["name": "Leg", "joints": [3, 4]]],
        "animations": [[
            "name": "Walk",
            "samplers": [["input": 1, "output": 0, "interpolation": "LINEAR"]],
            "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
        ]],
        "nodes": [
            [
                "name": "Root",
                "children": [1, 2, 3],
                "matrix": [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 1, 2, 3, 1],
            ],
            ["name": "Boxed", "mesh": 0, "translation": [1, 2, 3], "scale": [2, 2, 2]],
            ["name": "Lamp", "extensions": ["KHR_lights_punctual": ["light": 0]]],
            ["name": "Hip", "children": [4]],
            ["name": "Knee"],
        ],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
}

private func instanceForestJSON(count: Int) -> [String: Any] {
    var nodes: [[String: Any]] = [[
        "name": "Root",
        "children": Array(1..<count),
    ]]
    for index in 1..<count {
        let kind = index % 4
        let matrix: [Double]
        switch kind {
        case 0:
            matrix = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, Double(index), 0, 0, 1]
        case 1:
            matrix = [2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 0, Double(index), 0, 1]
        case 2:
            matrix = [-2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 0, 0, Double(index), 1]
        default:
            matrix = [
                53.0964, 0, 0, 0,
                0, -31.2167, -42.9505, 0,
                0, 42.9505, -31.2167, 0,
                Double(index), 5.73115, -69.3003, 1,
            ]
        }
        nodes.append(["name": "I\(index)", "matrix": matrix])
    }
    return [
        "asset": ["version": "2.0"],
        "nodes": nodes,
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
}

private func texturedPreviewGLB() throws -> Data {
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
