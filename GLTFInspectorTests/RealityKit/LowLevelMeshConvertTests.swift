import Foundation
import GLTFKit2
import RealityKit
@testable import RendererRealityKit
import Testing

/// `LowLevelMesh` rejects `vertexBufferCount` 5. A primitive with position + normal +
/// tangent + uv0 + (uv1 or color) must still take that path, not MeshDescriptor.
@MainActor
struct LowLevelMeshConvertTests {
    @Test func fiveAttributePrimitiveConvertsViaLowLevelMesh() async throws {
        let component = try #require(try convertLowLevelMesh(
            attributes: [.position, .normal, .tangent, .uv0, .color]
        ))
        #expect(!component.mesh.bounds.isEmpty)
    }

    @Test func sixAttributePrimitiveConvertsViaLowLevelMesh() async throws {
        let component = try #require(try convertLowLevelMesh(
            attributes: [.position, .normal, .tangent, .uv0, .uv1, .color]
        ))
        #expect(!component.mesh.bounds.isEmpty)
    }
}

private enum MeshAttr {
    case position, normal, tangent, uv0, uv1, color
}

@MainActor
private func convertLowLevelMesh(attributes: [MeshAttr]) throws -> ModelComponent? {
    let url = try TestGLB.writeTemp(try attributeTriangleGLB(attributes), prefix: "llmesh")
    defer { try? FileManager.default.removeItem(at: url) }
    let asset = try GLTFAsset(
        url: url,
        options: [GLTFAssetLoadingOption.assetDirectoryURLKey: url.deletingLastPathComponent()]
    )
    let mesh = try #require(asset.meshes.first)
    return try RealityKitConvert().convertLowLevelMesh(mesh, context: RealityKitResourceContext())
}

private func attributeTriangleGLB(_ attributes: [MeshAttr]) throws -> Data {
    var bin = Data()
    var views: [[String: Any]] = []
    var accessors: [[String: Any]] = []
    var names: [String: Int] = [:]

    func appendView(byteLength: Int) {
        views.append(["buffer": 0, "byteOffset": bin.count - byteLength, "byteLength": byteLength])
    }

    func addFloats(_ values: [Float], type: String, min: [Float]? = nil, max: [Float]? = nil) {
        let start = bin.count
        appendFloats(values, to: &bin)
        appendView(byteLength: bin.count - start)
        var accessor: [String: Any] = [
            "bufferView": views.count - 1,
            "componentType": 5126,
            "count": 3,
            "type": type,
        ]
        if let min { accessor["min"] = min }
        if let max { accessor["max"] = max }
        accessors.append(accessor)
    }

    for attribute in attributes {
        switch attribute {
        case .position:
            addFloats([0, 0, 0, 1, 0, 0, 0, 1, 0], type: "VEC3", min: [0, 0, 0], max: [1, 1, 0])
            names["POSITION"] = accessors.count - 1
        case .normal:
            addFloats([0, 0, 1, 0, 0, 1, 0, 0, 1], type: "VEC3")
            names["NORMAL"] = accessors.count - 1
        case .tangent:
            addFloats([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1], type: "VEC4")
            names["TANGENT"] = accessors.count - 1
        case .uv0:
            addFloats([0, 0, 1, 0, 0, 1], type: "VEC2")
            names["TEXCOORD_0"] = accessors.count - 1
        case .uv1:
            addFloats([0, 1, 1, 1, 0, 0], type: "VEC2")
            names["TEXCOORD_1"] = accessors.count - 1
        case .color:
            addFloats([1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1], type: "VEC4")
            names["COLOR_0"] = accessors.count - 1
        }
    }

    let indexStart = bin.count
    for value: UInt16 in [0, 1, 2] {
        var bits = value.littleEndian
        withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    appendView(byteLength: bin.count - indexStart)
    accessors.append([
        "bufferView": views.count - 1,
        "componentType": 5123,
        "count": 3,
        "type": "SCALAR",
    ])

    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": views,
        "accessors": accessors,
        "meshes": [["primitives": [[
            "attributes": names,
            "indices": accessors.count - 1,
        ]]]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.serialize(json: json, bin: bin)
}
