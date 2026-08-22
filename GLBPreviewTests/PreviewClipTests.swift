import Foundation
import RealityKit
import Testing
@testable import GLBPreview

struct PreviewClipTests {
    @Test func listFromDocumentSkipsZeroDurationAndTitlesEmpty() {
        var document = GLTFSessionDocument()
        document.animations = [
            .init(name: "Walk", duration: 1.5),
            .init(name: "", duration: 0),
            .init(name: "  ", duration: 2.0),
        ]
        let clips = PreviewClip.list(from: document)
        #expect(clips.map(\.title) == ["Walk", "Clip 3"])
        #expect(clips.map(\.id) == [0, 2])
        #expect(clips[0].duration == 1.5)
        #expect(clips[1].duration == 2.0)
    }

    @MainActor
    @Test func usableMatchesDocumentAnimationNames() async throws {
        let url = try writePreviewClipTwoClipGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        let usable = PreviewClip.usable(on: model.entity, document: model.document)
        let fromDocument = PreviewClip.list(from: model.document)

        #expect(usable.count == 2)
        #expect(fromDocument.count == 2)
        #expect(usable.map(\.name) == ["ClipA", "ClipB"])
        #expect(usable.map(\.title) == fromDocument.map(\.title))
        #expect(usable.map(\.title) == ["ClipA", "ClipB"])
        #expect(usable.map(\.id) == fromDocument.map(\.id))
        #expect(usable.allSatisfy { $0.duration > 0 })
        #expect(model.document.animations.map(\.name) == ["ClipA", "ClipB"])
    }

    @MainActor
    @Test func boxAnimatedExposesUsableClips() async throws {
        let url = TestFixtures.boxAnimated
        #expect(FileManager.default.fileExists(atPath: url.path))

        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        let usable = PreviewClip.usable(on: model.entity, document: model.document)
        let fromDocument = PreviewClip.list(from: model.document)

        #expect(!usable.isEmpty)
        #expect(usable.count == fromDocument.count)
        #expect(usable.map(\.title) == fromDocument.map(\.title))
        #expect(usable.map(\.id) == fromDocument.map(\.id))
        #expect(usable.allSatisfy { $0.duration > 0 })
    }
}


private func writePreviewClipTwoClipGLB() throws -> URL {
    var bin = Data()
    appendPreviewClipFloats([0, 0, 0, 1, 0, 0, 0, 1, 0], to: &bin)
    let positionLength = bin.count
    appendPreviewClipFloats([0, 1], to: &bin)
    let timeALength = 8
    appendPreviewClipFloats([0, 0, 0, 1, 0, 0], to: &bin)
    let transALength = 24
    appendPreviewClipFloats([0, 2], to: &bin)
    let timeBLength = 8
    appendPreviewClipFloats([0, 0, 0, 0, 1, 0], to: &bin)
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
            ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"],
            [
                "bufferView": 1,
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
                "min": [0.0],
                "max": [1.0],
            ],
            ["bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC3"],
            [
                "bufferView": 3,
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
                "min": [0.0],
                "max": [2.0],
            ],
            ["bufferView": 4, "componentType": 5126, "count": 2, "type": "VEC3"],
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
    let data = try GLBBox.serialize(json: json, bin: bin)
    return try GLBBox.writePrepared(data, prefix: "preview-clip")
}

private func appendPreviewClipFloats(_ values: [Float], to data: inout Data) {
    for value in values {
        var v = value
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
}
