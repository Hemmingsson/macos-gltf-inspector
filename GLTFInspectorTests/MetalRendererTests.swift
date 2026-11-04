import CoreGraphics
import Foundation
import GLTFCore
import simd
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

    private func frontPose() -> MetalCameraPose {
        MetalCameraPose(azimuth: 0, elevation: 0, distance: 5, target: SIMD3(0, 0, 0),
                        yfov: .pi / 3, znear: 0.1, zfar: 100)
    }

    @Test func xrayStackedQuadsMatchRegardlessOfFileOrder() async throws {
        let forwardURL = try writeTempStackedQuadsGLB(sceneNodeOrder: [0, 1], prefix: "xray-render-fwd")
        let reversedURL = try writeTempStackedQuadsGLB(sceneNodeOrder: [1, 0], prefix: "xray-render-rev")
        defer {
            try? FileManager.default.removeItem(at: forwardURL)
            try? FileManager.default.removeItem(at: reversedURL)
        }
        let options = ViewOptions(viewMode: .xray)
        let pose = frontPose()
        let size = 64
        let renderer = try MetalRenderer()
        try await renderer.load(url: forwardURL)
        let forward = try PixelDiff.raster(from: renderer.image(options, pose: pose, width: size, height: size))
        try await renderer.load(url: reversedURL)
        let reversed = try PixelDiff.raster(from: renderer.image(options, pose: pose, width: size, height: size))
        #expect(forward == reversed)
    }

    @Test func xrayMaskKeepsCenterCutout() async throws {
        let url = try writeTempMaskOverOpaqueGLB(prefix: "xray-mask-cutout")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        let pose = frontPose()
        let xray = ViewOptions(viewMode: .xray)
        let xrayBackOnly = ViewOptions(viewMode: .xray, hiddenNodeIndices: [1])
        let shaded = ViewOptions(viewMode: .shaded)
        let shadedBackOnly = ViewOptions(hiddenNodeIndices: [1])
        let xrayRaster = try PixelDiff.raster(from: renderer.image(xray, pose: pose, width: size, height: size))
        let xrayBackRaster = try PixelDiff.raster(from: renderer.image(xrayBackOnly, pose: pose, width: size, height: size))
        let shadedRaster = try PixelDiff.raster(from: renderer.image(shaded, pose: pose, width: size, height: size))
        let shadedBackRaster = try PixelDiff.raster(from: renderer.image(shadedBackOnly, pose: pose, width: size, height: size))
        let center = (size / 2 * size + size / 2) * 4
        #expect(Array(xrayRaster.bytes[center..<center + 3]) == Array(xrayBackRaster.bytes[center..<center + 3]))
        #expect(Array(shadedRaster.bytes[center..<center + 3]) == Array(shadedBackRaster.bytes[center..<center + 3]))
        #expect(xrayRaster.bytes != xrayBackRaster.bytes, "opaque mask texels must still draw over the back quad")
    }

    @Test func clayIgnoresVertexColor() async throws {
        let url = try writeTempVertexColorQuadGLB(prefix: "clay-vertex-color")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        let pose = frontPose()
        let clay = try PixelDiff.raster(from: renderer.image(ViewOptions(viewMode: .clay), pose: pose, width: size, height: size))
        let shaded = try PixelDiff.raster(from: renderer.image(ViewOptions(viewMode: .shaded), pose: pose, width: size, height: size))
        #expect(clay != shaded, "Shaded should still show vertex colour tints")
        func rgbSpread(_ raster: PixelDiff.Raster) -> Int {
            var minC = 255, maxC = 0
            for i in stride(from: 0, to: raster.bytes.count, by: 4) where raster.bytes[i + 3] > 0 {
                for channel in 0..<3 {
                    let value = Int(raster.bytes[i + channel])
                    minC = min(minC, value)
                    maxC = max(maxC, value)
                }
            }
            return maxC - minC
        }
        #expect(rgbSpread(shaded) >= 40, "Vertex colours should tint shaded output")
        #expect(rgbSpread(clay) <= 20, "Clay should not inherit corner colour tints")
    }

    @Test func repeatedFramesReuseGPURenderTargets() async throws {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first(where: { $0.name == "BoomBox" }))
        let renderer = try MetalRenderer()
        try await renderer.load(url: entry.modelURL)
        let options = ViewOptions(look: try PixelDiffMetal.renderLook(manifest.look))
        let pose = MetalCameraPose(try PixelDiffRun.camera(of: entry))
        let width = 128, height = 128
        renderer.resetTextureAllocationCount()
        _ = try renderer.renderTexture(options, pose: pose, width: width, height: height)
        let firstFrameAllocations = renderer.textureAllocationCount
        #expect(firstFrameAllocations > 0)
        for _ in 0..<2 {
            renderer.resetTextureAllocationCount()
            _ = try renderer.renderTexture(options, pose: pose, width: width, height: height)
            #expect(renderer.textureAllocationCount == 0)
        }
    }

    @Test func repeatedPicksReusePickTargets() async throws {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first(where: { $0.name == "BoomBox" }))
        let renderer = try MetalRenderer()
        try await renderer.load(url: entry.modelURL)
        let options = ViewOptions(look: try PixelDiffMetal.renderLook(manifest.look))
        let pose = MetalCameraPose(try PixelDiffRun.camera(of: entry))
        let point = SIMD2(64, 64)
        renderer.resetTextureAllocationCount()
        _ = try renderer.pick(options, pose: pose, width: 128, height: 128, point: point)
        #expect(renderer.textureAllocationCount > 0)
        renderer.resetTextureAllocationCount()
        _ = try renderer.pick(options, pose: pose, width: 128, height: 128, point: point)
        #expect(renderer.textureAllocationCount == 0)
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
