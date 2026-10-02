import CoreGraphics
import Foundation
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

struct PreviewClipTests {
    @MainActor
    @Test func usableMatchesDocumentAnimationNames() async throws {
        let url = try writePreviewClipTwoClipGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        let usable = PreviewClip.usable(on: model.entity, document: model.document)

        #expect(usable.count == 2)
        #expect(usable.map(\.name) == ["ClipA", "ClipB"])
        #expect(usable.map(\.title) == ["ClipA", "ClipB"])
        #expect(usable.map(\.id) == [0, 1])
        #expect(usable.allSatisfy { $0.duration > 0 })
        #expect(model.document.animations.map(\.name) == ["ClipA", "ClipB"])
    }

    @MainActor
    @Test func boxAnimatedExposesUsableClips() async throws {
        let url = TestFixtures.boxAnimated
        #expect(FileManager.default.fileExists(atPath: url.path))

        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        let usable = PreviewClip.usable(on: model.entity, document: model.document)

        #expect(!usable.isEmpty)
        #expect(usable.count == model.document.animations.filter { $0.duration > 0 }.count)
        #expect(usable.allSatisfy { $0.duration > 0 })
    }

    /// PreviewScene poses clip 0 paused; the host player must replace that controller, not blend.
    @MainActor
    @Test func hostPlayReplacesPausedPoseController() async throws {
        let url = try writePreviewClipTwoClipGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        let clips = PreviewClip.usable(on: model.entity, document: model.document)
        let first = try #require(clips.first)
        let second = try #require(clips.dropFirst().first)
        #expect(first.id != second.id)

        let pose = model.entity.playAnimation(first.resource.repeat(), startsPaused: true)
        pose.time = first.duration
        #expect(!pose.isComplete)
        #expect(pose.isPaused)

        let player = RealityClipPlayer(model: model)
        #expect(player.start(clipID: second.id, playing: false))
        player.time = second.duration
        #expect(pose.isComplete)

        let root = try #require(namedEntity("Root", in: model.entity))
        _ = try await StillRenderer.render(
            root: model.entity,
            cameraPose: StillCameraPose(
                position: [0, 0, 5],
                orientation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                projection: .perspective(fieldOfViewDegrees: 45, near: 0.1, far: 100)
            ),
            width: 16,
            height: 16,
            background: CGColor(gray: 0.5, alpha: 1)
        )
        let p = root.position(relativeTo: nil)
        #expect(abs(p.x) < 0.05, "expected clip B end (0,1,0), got \(p)")
        #expect(abs(p.y - 1) < 0.05, "expected clip B end (0,1,0), got \(p)")
        #expect(abs(p.z) < 0.05, "expected clip B end (0,1,0), got \(p)")
    }
}


private func writePreviewClipTwoClipGLB() throws -> URL {
    var bin = Data()
    appendFloats([0, 0, 0, 1, 0, 0, 0, 1, 0], to: &bin)
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
    let data = try TestGLB.serialize(json: json, bin: bin)
    return try TestGLB.writeTemp(data, prefix: "preview-clip")
}

