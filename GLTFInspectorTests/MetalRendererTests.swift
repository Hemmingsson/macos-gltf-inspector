import CoreGraphics
import Foundation
import GLTFCore
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct MetalRendererTests {
    @Test func rendersRealModelOffscreenWithTransparentBackground() async throws {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first(where: { $0.name == "BoomBox" }))
        let renderer = try MetalRenderer()
        try await renderer.load(url: entry.modelURL)
        let image = try renderer.image(
            ViewOptions(look: try PixelDiffMetal.renderLook(manifest.look)),
            pose: MetalCameraPose(try PixelDiffRun.camera(of: entry)), width: 256, height: 256
        )
        #expect(image.width == 256 && image.height == 256)
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        let data = try #require(image.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let alphaIndex = image.alphaInfo == .first || image.alphaInfo == .premultipliedFirst ? 0 : 3
        var transparent = 0, covered = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let alpha = bytes[y * image.bytesPerRow + x * 4 + alphaIndex]
                if alpha == 0 { transparent += 1 }
                if alpha > 0 { covered += 1 }
            }
        }
        #expect(transparent > 100, "offscreen image must retain its transparent backdrop")
        #expect(covered > 100, "offscreen image must contain model geometry")
        try FileManager.default.createDirectory(at: PixelDiffPaths.outputDirectory, withIntermediateDirectories: true)
        try PixelDiff.write(
            PixelDiff.raster(from: image),
            to: PixelDiffPaths.outputDirectory.appendingPathComponent("Metal-BoomBox-smoke.png")
        )
    }

    @Test func repeatingAStillIsDeterministic() async throws {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first(where: { $0.name == "BoomBox" }))
        let renderer = try MetalRenderer()
        try await renderer.load(url: entry.modelURL)
        let options = ViewOptions(look: try PixelDiffMetal.renderLook(manifest.look))
        let pose = MetalCameraPose(try PixelDiffRun.camera(of: entry))
        let first = try PixelDiff.raster(from: renderer.image(options, pose: pose, width: 128, height: 128))
        let second = try PixelDiff.raster(from: renderer.image(options, pose: pose, width: 128, height: 128))
        #expect(first == second)
    }

    @Test func everyPinnedSampleRendersWithoutGPUFailure() async throws {
        let manifest = try PixelDiffManifest.load()
        let renderer = try MetalRenderer()
        let options = ViewOptions(look: try PixelDiffMetal.renderLook(manifest.look))
        for entry in manifest.entries {
            try #require(FileManager.default.fileExists(atPath: entry.modelURL.path),
                         "Missing \(entry.name): ./scripts/fetch-test-models.sh")
            try await renderer.load(url: entry.modelURL)
            let image = try renderer.image(
                options, pose: MetalCameraPose(try PixelDiffRun.camera(of: entry)), width: 64, height: 64
            )
            #expect(image.width == 64 && image.height == 64, "\(entry.name) produced the wrong size")
            print("metal smoke \(entry.name): 64x64")
        }
    }

    @Test func damagedFileThrowsRatherThanRenderingABlank() async throws {
        let renderer = try MetalRenderer()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metal-corrupt-\(UUID()).glb")
        try Data([0, 1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: (any Error).self) {
            try await renderer.load(url: url)
        }
    }
}
