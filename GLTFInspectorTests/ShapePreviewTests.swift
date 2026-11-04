import AppKit
import Foundation
import Metal
import Testing
@testable import GLTFCore
@testable import GLTFInspector
@testable import Renderer

@MainActor
@Suite(.serialized)
struct ShapePreviewTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    private func drawnNodes(_ options: ViewOptions, in scene: MetalScene) -> [Int] {
        let mask = MetalDrawFilter(options).visibleDraws(in: scene)
        return zip(scene.draws, mask).filter { $0.1 }.map { $0.0.nodeIndex }.sorted()
    }

    private func settings() throws -> AppSettings {
        let suite = "gltf.shape-preview.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    @Test func previewIsolatesEachMeshWithoutChangingCanvasOptions() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let state = ViewState(settings: try settings())
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        state.canvas.mount(in: container, url: url, options: state.options)
        try #require(try await waitUntil { state.canvas.phase == .ready })
        defer { state.canvas.view?.removeFromSuperview() }

        let canvasOptionsBefore = state.canvas.view!.options
        #expect(canvasOptionsBefore.isolatedNodeIndex == nil)

        for nodeIndex in [0, 1] {
            let selection = NodeID(kind: .mesh, index: nodeIndex)
            await state.shapePreview.sync(canvas: state.canvas, windowOptions: state.options, selection: selection)
            guard let preview = state.shapePreview.view, let scene = state.canvas.scene else {
                Issue.record("preview or scene missing")
                return
            }
            #expect(preview.options.isolatedNodeIndex == nodeIndex)
            #expect(drawnNodes(preview.options, in: scene) == [nodeIndex])
            #expect(!preview.options.showsFloor)
            #expect(!preview.options.showsSceneGizmos)
            #expect(preview.options.isCentered)
        }

        #expect(state.canvas.view!.options.isolatedNodeIndex == nil)
        #expect(state.canvas.view!.options == canvasOptionsBefore)
    }

    @Test func exposureChangeKeepsOrbitAndDoesNotReAdopt() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let state = ViewState(settings: try settings())
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        state.canvas.mount(in: container, url: url, options: ViewOptions())
        try #require(try await waitUntil { state.canvas.phase == .ready })
        defer { state.canvas.view?.removeFromSuperview() }

        let selection = NodeID(kind: .mesh, index: 0)
        await state.shapePreview.sync(canvas: state.canvas, windowOptions: state.options, selection: selection)
        let preview = try #require(state.shapePreview.view)
        preview.orbit(dx: 120, dy: 60)
        let azimuth = preview.camera.rotAroundY
        let elevation = preview.camera.rotAroundX
        #expect(azimuth != 0)
        let adoptsBefore = state.shapePreview.adoptCount

        state.exposure = 1.5
        await state.shapePreview.sync(canvas: state.canvas, windowOptions: state.options, selection: selection)

        #expect(preview.camera.rotAroundY == azimuth)
        #expect(preview.camera.rotAroundX == elevation)
        #expect(state.shapePreview.adoptCount == adoptsBefore)
    }

    @Test func previewModelViewStaysStableAcrossSelectionAndReAdoptsOnReload() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let state = ViewState(settings: try settings())
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        state.canvas.mount(in: container, url: url, options: ViewOptions())
        try #require(try await waitUntil { state.canvas.phase == .ready })
        defer { state.canvas.view?.removeFromSuperview() }

        await state.shapePreview.sync(canvas: state.canvas, windowOptions: state.options,
                                      selection: NodeID(kind: .mesh, index: 0))
        let firstPreview = try #require(state.shapePreview.view)
        let firstID = ObjectIdentifier(firstPreview)

        await state.shapePreview.sync(canvas: state.canvas, windowOptions: state.options,
                                      selection: NodeID(kind: .mesh, index: 1))
        #expect(ObjectIdentifier(try #require(state.shapePreview.view)) == firstID)

        let generationAfterLoad = state.canvas.sceneGeneration
        state.canvas.update(url: TestFixtures.cube, options: ViewOptions())
        try #require(try await waitUntil { state.canvas.sceneGeneration > generationAfterLoad })

        await state.shapePreview.sync(canvas: state.canvas, windowOptions: state.options,
                                      selection: NodeID(kind: .mesh, index: 0))
        #expect(ObjectIdentifier(try #require(state.shapePreview.view)) == firstID)
        #expect(state.shapePreview.view?.renderer.scene?.draws.count == 1)
        #expect(try centreAlpha(try firstPreview.image(width: 128, height: 128)) > 200)
    }
}
