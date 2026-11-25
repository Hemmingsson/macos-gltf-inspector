import Foundation
@testable import GLTFCore
import Testing

struct GLTFCoreMalformedInputTests {
    @Test func glbRequiresVersionTwoAndDeclaredLength() throws {
        let json = #"{"asset":{"version":"2.0"}}"#.data(using: .utf8)!
        var data = glb(json: json, bin: nil)

        data.replaceSubrange(4..<8, with: littleEndian(1))
        #expect(throws: (any Error).self) { try GLBBox.parse(data) }

        data = glb(json: json, bin: nil)
        data.replaceSubrange(8..<12, with: littleEndian(UInt32(data.count + 4)))
        #expect(throws: (any Error).self) { try GLBBox.parse(data) }
    }

    @Test func glbRequiresOneJsonChunkBeforeBin() throws {
        let json = #"{"asset":{"version":"2.0"}}"#.data(using: .utf8)!
        let bin = Data([1, 2, 3, 4])
        let malformed = glbChunks([
            (Data("BIN\0".utf8), bin),
            (Data("JSON".utf8), json),
        ])
        #expect(throws: (any Error).self) { try GLBBox.parse(malformed) }
    }

    @Test func loadPreservesOpaqueCustomMetadata() async throws {
        let metadata: [String: Any] = [
            "source": "Blender", "count": "many", "nodes": "custom", "color": "blue",
        ]
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "extras": metadata,
            "nodes": [["name": "Custom metadata", "extras": metadata]],
            "materials": [["extras": metadata]],
            "extensions": ["VENDOR_custom": metadata,
                "KHR_materials_variants": ["variants": [["name": "Variant"]]]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try await GLTFDocument.load(from: url)
        #expect(document.nodes.first?.name == "Custom metadata")
        #expect(document.materials.count == 1)
        #expect(document.materialVariantNames == ["Variant"])
    }

    @Test func loadStillRejectsInvalidKnownExtensionReferences() async throws {
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "extensions": ["KHR_materials_variants": ["variants": [["name": "Variant"]]]],
            "meshes": [["primitives": [["extensions": [
                "KHR_materials_variants": ["mappings": [["material": "invalid", "variants": [0]]]],
            ]]]]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) { try await GLTFDocument.load(from: url) }
    }

    @Test func loadAcceptsScalarNormalTextureScaleAlongsideNodeScale() async throws {
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "nodes": [["name": "Scaled", "scale": [2.0, 3.0, 4.0]]],
            "materials": [["normalTexture": ["index": 0, "scale": 0.5]]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try await GLTFDocument.load(from: url)
        #expect(document.materials.first?.normalScale == 0.5)
        #expect(document.nodes.first?.scale.x == 2)
    }

    @Test func loadRejectsArrayNormalTextureScale() async throws {
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "materials": [["normalTexture": ["index": 0, "scale": [1, 1, 1]]]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) { try await GLTFDocument.load(from: url) }
    }

    @Test func loadRejectsNegativeAccessorCount() async throws {
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "accessors": [["componentType": 5126, "count": -1, "type": "SCALAR"]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) { try await GLTFDocument.load(from: url) }
    }

    @Test func loadRejectsAccessorCountThatCannotFitItsBufferView() async throws {
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "buffers": [["uri": "data:application/octet-stream;base64,AAAA", "byteLength": 4]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 4]],
            "accessors": [[
                "bufferView": 0,
                "componentType": 5126,
                "count": 9_223_372_036_854_775_807,
                "type": "SCALAR",
            ]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) { try await GLTFDocument.load(from: url) }
    }

    @Test func loadRejectsExternalUriTraversal() async throws {
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "buffers": [["uri": "../outside.bin", "byteLength": 4]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) { try await GLTFDocument.load(from: url) }
    }

    @Test func loadRejectsBufferViewOutsideDeclaredBufferLength() async throws {
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "buffers": [["uri": "data:application/octet-stream;base64,AAAA", "byteLength": 4]],
            "bufferViews": [["buffer": 0, "byteOffset": 4, "byteLength": 1]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) { try await GLTFDocument.load(from: url) }
    }

    @Test func loadRejectsBufferViewIntegerOverflow() async throws {
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "buffers": [["uri": "data:application/octet-stream;base64,AAAA", "byteLength": 4]],
            "bufferViews": [["buffer": 0, "byteOffset": Int.max, "byteLength": 1]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) { try await GLTFDocument.load(from: url) }
    }

    @Test func loadRejectsMalformedDataUri() async throws {
        let url = try writeTempGltf([
            "asset": ["version": "2.0"],
            "buffers": [["uri": "data:application/octet-stream;base64,%%%", "byteLength": 1]],
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) { try await GLTFDocument.load(from: url) }
    }

    @Test func loadRejectsOversizedPrimaryPayload() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("core-large-\(UUID().uuidString).gltf")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(GLTFResourceLimits.maxSourceBytes + 1))
        try handle.close()
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) { try await GLTFDocument.load(from: url) }
    }

    @Test func boundsTraversalStopsAtADeepChain() {
        let count = 10_000
        var nodes = [[String: Any]]()
        nodes.reserveCapacity(count)
        for index in 0..<count {
            nodes.append(index + 1 < count ? ["children": [index + 1]] : [:])
        }

        #expect(ModelBounds.from(json: [
            "scenes": [["nodes": [0]]],
            "nodes": nodes,
        ]) == nil)
    }

    @Test func animationDurationIsSamplerSpan() {
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "nodes": [["name": "Root"]],
            "accessors": [[
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
                "min": [5.0],
                "max": [6.0],
            ]],
            "animations": [[
                "name": "Offset",
                "samplers": [["input": 0]],
                "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
            ]],
        ])

        #expect(document.animations.first?.duration == 1)
    }

    @Test func boundsTraversalHandlesCycles() {
        let json: [String: Any] = [
            "scenes": [["nodes": [0]]],
            "nodes": [["children": [1]], ["children": [0]]],
        ]

        #expect(ModelBounds.from(json: json) == nil)
    }

    private func writeTempGltf(_ json: [String: Any]) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: json)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("core-malformed-\(UUID().uuidString).gltf")
        try data.write(to: url)
        return url
    }

    private func glb(json: Data, bin: Data?) -> Data {
        glbChunks([(Data("JSON".utf8), json), (Data("BIN\0".utf8), bin)].compactMap { chunk in
            chunk.1.map { (chunk.0, $0) }
        })
    }

    private func glbChunks(_ chunks: [(Data, Data)]) -> Data {
        var data = Data("glTF".utf8)
        data.append(littleEndian(UInt32(2)))
        let lengthOffset = data.count
        data.append(littleEndian(0))
        for (type, payload) in chunks {
            data.append(littleEndian(UInt32(payload.count)))
            data.append(type)
            data.append(payload)
        }
        data.replaceSubrange(lengthOffset..<lengthOffset + 4, with: littleEndian(UInt32(data.count)))
        return data
    }

    private func littleEndian(_ value: UInt32) -> Data {
        var value = value.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}
