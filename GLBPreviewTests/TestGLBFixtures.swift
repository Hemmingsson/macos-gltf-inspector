import AppKit
import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

@MainActor
func pbrMaterials(in entity: Entity) -> [PhysicallyBasedMaterial] {
    var out: [PhysicallyBasedMaterial] = []
    if let model = entity.components[ModelComponent.self] {
        for material in model.materials {
            if let pbr = material as? PhysicallyBasedMaterial {
                out.append(pbr)
            }
        }
    }
    for child in entity.children {
        out.append(contentsOf: pbrMaterials(in: child))
    }
    return out
}

/// Three vertices. Mode 4 = TRIANGLES (legal). Mode 1 = LINES, 5 = TRIANGLE_STRIP.
func primitiveModeGLB(mode: Int) throws -> Data {
    var bin = Data()
    for value: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
            "min": [0, 0, 0],
            "max": [1, 1, 0],
        ]],
        "meshes": [["primitives": [[
            "attributes": ["POSITION": 0],
            "mode": mode,
        ]]]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}

func shortTriangleGLB() throws -> Data {
    var bin = Data()
    // 3 SHORT VEC3 positions: (0,0,0) (100,0,0) (0,100,0)
    for value in [Int16(0), 0, 0, Int16(100), 0, 0, Int16(0), 100, 0] {
        var bits = value.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [[
            "buffer": 0,
            "byteOffset": 0,
            "byteLength": bin.count,
        ]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5122,
            "count": 3,
            "type": "VEC3",
            "max": [100, 100, 0],
            "min": [0, 0, 0],
        ]],
        "meshes": [[
            "primitives": [[
                "attributes": ["POSITION": 0],
            ]],
        ]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}

func metalRoughTriangleGLB() throws -> Data {
    var bin = Data()
    for value in [Int16(0), 0, 0, Int16(100), 0, 0, Int16(0), 100, 0] {
        var bits = value.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [[
            "buffer": 0,
            "byteOffset": 0,
            "byteLength": bin.count,
        ]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5122,
            "count": 3,
            "type": "VEC3",
            "max": [100, 100, 0],
            "min": [0, 0, 0],
        ]],
        "materials": [[
            "pbrMetallicRoughness": [
                "baseColorFactor": [0.85, 0.8, 0.7, 1],
                "metallicFactor": 0,
                "roughnessFactor": 0.35,
            ],
        ]],
        "meshes": [[
            "primitives": [[
                "attributes": ["POSITION": 0],
                "material": 0,
            ]],
        ]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}

func tinyPNG() -> Data {
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
}

func texturedPBRTriangleGLB(
    extensionsUsed: [String] = [],
    material: [String: Any],
    uvs: [(Float, Float)]? = nil
) throws -> Data {
    var bin = Data()
    for value in [Int16(0), 0, 0, Int16(100), 0, 0, Int16(0), 100, 0] {
        var bits = value.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let positionsLength = bin.count
    if let uvs {
        for (u, v) in uvs {
            for value in [u, v] {
                var bits = value.bitPattern.littleEndian
                Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
            }
        }
    }
    let png = tinyPNG()
    let pngStart = bin.count
    bin.append(png)
    var bufferViews: [[String: Any]] = [
        ["buffer": 0, "byteOffset": 0, "byteLength": positionsLength],
    ]
    var accessors: [[String: Any]] = [[
        "bufferView": 0,
        "componentType": 5122,
        "count": 3,
        "type": "VEC3",
        "max": [100, 100, 0],
        "min": [0, 0, 0],
    ]]
    var attributes: [String: Any] = ["POSITION": 0]
    if let uvs {
        bufferViews.append([
            "buffer": 0,
            "byteOffset": positionsLength,
            "byteLength": uvs.count * 8,
        ])
        accessors.append([
            "bufferView": 1,
            "componentType": 5126,
            "count": uvs.count,
            "type": "VEC2",
        ])
        attributes["TEXCOORD_0"] = 1
        bufferViews.append([
            "buffer": 0,
            "byteOffset": pngStart,
            "byteLength": png.count,
        ])
    } else {
        bufferViews.append([
            "buffer": 0,
            "byteOffset": positionsLength,
            "byteLength": png.count,
        ])
    }
    let imageView = bufferViews.count - 1
    var json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": bufferViews,
        "accessors": accessors,
        "images": [["mimeType": "image/png", "bufferView": imageView]],
        "textures": [["source": 0]],
        "materials": [material],
        "meshes": [[
            "primitives": [[
                "attributes": attributes,
                "material": 0,
            ]],
        ]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    if !extensionsUsed.isEmpty {
        json["extensionsUsed"] = extensionsUsed
    }
    return try GLBBox.serialize(json: json, bin: bin)
}

func hasVisibleEmissive(_ material: PhysicallyBasedMaterial) -> Bool {
    if material.emissiveColor.texture != nil { return true }
    guard let components = material.emissiveColor.color.cgColor.components, components.count >= 3 else {
        return false
    }
    return max(components[0], max(components[1], components[2])) > 0.05
}

@MainActor
func loadFirstPBR(_ glb: Data) async throws -> PhysicallyBasedMaterial {
    let all = try await loadAllPBR(glb)
    try #require(!all.isEmpty)
    return all[0]
}

@MainActor
func loadModel(_ glb: Data, includeAnimations: Bool = false) async throws -> EntityLoader.LoadedModel {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("load-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("m.glb")
    try glb.write(to: url)
    return try await EntityLoader.load(from: url, includeAnimations: includeAnimations)
}

@MainActor
func firstComponent<T: Component>(_ type: T.Type, in entity: Entity) -> T? {
    if let found = entity.components[type] { return found }
    for child in entity.children {
        if let found = firstComponent(type, in: child) { return found }
    }
    return nil
}

func appendFloats(_ values: [Float], to data: inout Data) {
    for value in values {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }
}

func floatTrianglePositions() -> [Float] {
    [0, 0, 0, 1, 0, 0, 0, 1, 0]
}

func floatTriangleBin() -> Data {
    var bin = Data()
    appendFloats(floatTrianglePositions(), to: &bin)
    return bin
}

func writeTempOneNodeMeshGLB(nodeName: String, prefix: String = "one-node") throws -> URL {
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
        "meshes": [["name": "HelmetMesh", "primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": [["name": nodeName, "mesh": 0]],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.writePrepared(try GLBBox.serialize(json: json, bin: bin), prefix: prefix)
}

@MainActor
func entity(nodeIndex: Int, in root: Entity) -> Entity? {
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

@MainActor
func namedEntity(_ name: String, in entity: Entity) -> Entity? {
    if entity.name == name { return entity }
    for child in entity.children {
        if let found = namedEntity(name, in: child) { return found }
    }
    return nil
}

@MainActor
func stampedNodeIndices(in entity: Entity) -> Set<Int> {
    var found = Set<Int>()
    func walk(_ node: Entity) {
        if let id = node.components[GLTFNodeIDComponent.self]?.nodeIndex {
            found.insert(id)
        }
        node.children.forEach(walk)
    }
    walk(entity)
    return found
}

@MainActor
func loadAllPBR(_ glb: Data) async throws -> [PhysicallyBasedMaterial] {
    pbrMaterials(in: try await loadModel(glb).entity)
}

@MainActor
func firstMeshUVs(in entity: Entity) -> [SIMD2<Float>]? {
    if let model = entity.components[ModelComponent.self] {
        for meshModel in model.mesh.contents.models {
            for part in meshModel.parts {
                if let uvs = part[MeshBuffers.textureCoordinates] {
                    return Array(uvs)
                }
            }
        }
    }
    for child in entity.children {
        if let uvs = firstMeshUVs(in: child) {
            return uvs
        }
    }
    return nil
}

func multiMaterialTriangleGLB(
    extensionsUsed: [String] = [],
    materials: [[String: Any]]
) throws -> Data {
    var bin = Data()
    for value in [Int16(0), 0, 0, Int16(100), 0, 0, Int16(0), 100, 0] {
        var bits = value.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    var json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [[
            "buffer": 0,
            "byteOffset": 0,
            "byteLength": bin.count,
        ]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5122,
            "count": 3,
            "type": "VEC3",
            "max": [100, 100, 0],
            "min": [0, 0, 0],
        ]],
        "materials": materials,
        "meshes": [[
            "primitives": materials.indices.map { index in
                [
                    "attributes": ["POSITION": 0],
                    "material": index,
                ]
            },
        ]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    if !extensionsUsed.isEmpty {
        json["extensionsUsed"] = extensionsUsed
    }
    return try GLBBox.serialize(json: json, bin: bin)
}

func instancedGLB(count: Int) throws -> Data {
    var bin = Data()
    for value: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let positionLength = bin.count
    // TRANSLATION instances along X
    for i in 0..<count {
        for value: Float in [Float(i), 0, 0] {
            var bits = value.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
        }
    }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": ["EXT_mesh_gpu_instancing"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionLength],
            ["buffer": 0, "byteOffset": positionLength, "byteLength": count * 12],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"],
            ["bufferView": 1, "componentType": 5126, "count": count, "type": "VEC3"],
        ],
        "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": [[
            "mesh": 0,
            "extensions": [
                "EXT_mesh_gpu_instancing": [
                    "attributes": ["TRANSLATION": 1],
                ],
            ],
        ]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}
