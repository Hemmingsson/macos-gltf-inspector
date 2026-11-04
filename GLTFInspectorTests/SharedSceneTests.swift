import AppKit
import Foundation
import Metal
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct SharedSceneTests {
    private func centreAlpha(_ image: CGImage) throws -> UInt8 {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let point = CGPoint(x: image.width / 2, y: image.height / 2)
        context.draw(image, in: CGRect(x: -point.x, y: -point.y, width: CGFloat(image.width), height: CGFloat(image.height)))
        return try #require(context.data?.assumingMemoryBound(to: UInt8.self))[3]
    }

    @Test func adoptSharesVertexAndIndexBuffers() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let source = ModelView(renderer: try MetalRenderer())
        try await source.load(url)
        guard let scene = source.renderer.scene else {
            Issue.record("source scene missing")
            return
        }
        #expect(scene.draws.count == 2)

        let preview = ModelView(renderer: try MetalRenderer(sharing: scene))
        try preview.show(scene: scene)

        for (sourceDraw, previewDraw) in zip(scene.draws, preview.renderer.scene!.draws) {
            #expect(ObjectIdentifier(sourceDraw.vertexBuffer) == ObjectIdentifier(previewDraw.vertexBuffer))
            #expect(ObjectIdentifier(sourceDraw.indexBuffer) == ObjectIdentifier(previewDraw.indexBuffer))
        }
        #expect(try centreAlpha(preview.image(width: 128, height: 128)) > 200)
    }

    @Test func reloadBumpsGenerationAndReAdoptShowsNewGeometry() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let canvas = ModelCanvasController()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 256, height: 256))
        canvas.mount(in: container, url: url, options: ViewOptions())
        _ = try await waitUntil { canvas.phase == .ready }
        let generationAfterLoad = canvas.sceneGeneration
        #expect(generationAfterLoad >= 1)
        guard let firstScene = canvas.scene else {
            Issue.record("canvas scene missing")
            return
        }
        #expect(firstScene.draws.count == 2)

        let preview = ModelView(renderer: try MetalRenderer(sharing: firstScene))
        try preview.show(scene: firstScene)

        var hidden = ViewOptions(hiddenNodeIndices: [0])
        canvas.update(url: url, options: hidden)
        _ = try await waitUntil { canvas.view?.options.hiddenNodeIndices == [0] }
        #expect(preview.renderer.scene?.draws.count == 2, "preview keeps full scene when source hides a node")
        let hiddenImage = try preview.image(width: 128, height: 128)
        #expect(try centreAlpha(hiddenImage) > 200)

        canvas.update(url: TestFixtures.cube, options: ViewOptions())
        _ = try await waitUntil { canvas.sceneGeneration > generationAfterLoad }
        guard let reloaded = canvas.scene else {
            Issue.record("reloaded scene missing")
            return
        }
        #expect(reloaded.draws.count == 1)
        try preview.show(scene: reloaded)
        #expect(preview.renderer.scene?.draws.count == 1)
        #expect(try centreAlpha(preview.image(width: 128, height: 128)) > 200)
    }

    @Test func disposingSourceLeavesPreviewRenderable() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        var source: ModelView? = ModelView(renderer: try MetalRenderer())
        try await source!.load(url)
        let scene = try #require(source?.renderer.scene)

        let preview = ModelView(renderer: try MetalRenderer(sharing: scene))
        try preview.show(scene: scene)
        #expect(try centreAlpha(preview.image(width: 128, height: 128)) > 200)

        source = nil
        #expect(try centreAlpha(preview.image(width: 128, height: 128)) > 200)
    }
}
