import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import RealityKit
@testable import RendererRealityKit
import Testing

/// Convert against the file document: node stamping, lazy scenes, clips. Fixtures live with the
/// document tests (`SessionDocumentTests.swift` at the test root).
struct SessionDocumentConvertTests {
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
    @Test func loadWithSceneIndexMatchesConvertSceneForMultiSceneFixture() async throws {
        let url = TestFixtures.multiScene

        let loaded = try await EntityLoader.load(from: url, includeAnimations: false, sceneIndex: 1)
        let converted = try await EntityLoader.convertScene(index: 1, from: url, includeAnimations: false)

        #expect(loaded.document.scenes.count == 2)
        #expect(stampedNodeIndices(in: loaded.entity) == stampedNodeIndices(in: converted))
        #expect(stampedNodeIndices(in: loaded.entity).contains(1))
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
        #expect(usable.map(\.title) == ["ClipA", "ClipB"])
        #expect(usable.map(\.id) == [0, 1])
        #expect(usable.map(\.name) == model.document.animations.map(\.name))
    }
}
