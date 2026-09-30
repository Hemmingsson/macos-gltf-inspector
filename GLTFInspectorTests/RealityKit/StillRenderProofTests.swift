import AppKit
import CoreGraphics
import Foundation
@testable import GLTFCore
@testable import RendererRealityKit
import Testing

/// In-process thumbnail proof. `qlmanage` can hang against a stale system plugin.
struct StillRenderProofTests {
    @MainActor
    @Test func stillRendererWritesTinyPNG() async throws {
        let url = TestFixtures.tiny
        try #require(FileManager.default.fileExists(atPath: url.path))

        let model = try await EntityLoader.loadThumbnail(from: url)
        let assembled = PreviewCamera.makeTurntable(for: model.entity)
        let still = try await StillRenderer(
            root: assembled.pivot,
            bounds: assembled.bounds,
            width: 256,
            height: 256,
            background: CGColor(gray: 0.94, alpha: 1),
            padding: PreviewCamera.thumbnailFitPadding,
            intensityExponent: model.studioIBLExponent
        )
        let image = try await still.capture()
        #expect(image.width == 256)
        #expect(image.height == 256)

        let out = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["GLB_PROOF_PNG"]
                ?? "/tmp/GLTFInspector-proof.png"
        )
        try PNGWriter.write(image, to: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
        #expect(try Self.modelCoverage(image) > 0.005, "tiny.glb rendered as an empty frame")
    }

    /// Committed multi-file sidecar (`cube.gltf` + `cube.bin` + `cube.png`) rendered
    /// end-to-end through GLTFKit2's own sidecar loading. A solid cube also stays visible from any turntable angle, unlike
    /// the flat `tiny.glb` triangle. Regenerate with `scripts/testdata/cube/make_cube.py`
    /// (writes `TestModels/Fixture Models/cube/`).
    @MainActor
    @Test func cubeSidecarRendersFromCommittedFiles() async throws {
        let url = TestFixtures.cube
        try #require(FileManager.default.fileExists(atPath: url.path))

        let model = try await EntityLoader.loadThumbnail(from: url)
        #expect(EntityLoader.modelComponentCount(in: model.entity) > 0)

        let assembled = PreviewCamera.makeTurntable(for: model.entity)
        let still = try await StillRenderer(
            root: assembled.pivot,
            bounds: assembled.bounds,
            width: 256,
            height: 256,
            background: CGColor(gray: 0.94, alpha: 1),
            padding: PreviewCamera.thumbnailFitPadding,
            intensityExponent: model.studioIBLExponent
        )
        let image = try await still.capture()
        #expect(image.width == 256)
        #expect(image.height == 256)

        let out = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["GLB_CUBE_PROOF_PNG"]
                ?? "/tmp/GLTFInspector-cube-proof.png"
        )
        try PNGWriter.write(image, to: out)
        #expect(try Self.modelCoverage(image) > 0.05, "cube rendered as an empty frame")
    }

    /// The still target stores sRGB-encoded bytes and is tagged sRGB, so an sRGB backdrop comes
    /// back unchanged. The old `.bgra8Unorm` + DeviceRGB path wrote scene-linear bytes and turned
    /// 128 into 55 (look probes, seam 5).
    @MainActor
    @Test func srgbBackdropRoundTrips() async throws {
        let model = try await EntityLoader.loadThumbnail(from: TestFixtures.tiny)
        let assembled = PreviewCamera.makeTurntable(for: model.entity)
        let still = try await StillRenderer(
            root: assembled.pivot,
            bounds: assembled.bounds,
            width: 64,
            height: 64,
            background: CGColor(srgbRed: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1),
            padding: PreviewCamera.thumbnailFitPadding
        )
        let raster = try PixelDiff.raster(from: try await still.capture())
        for channel in 0..<3 {
            #expect(abs(Int(raster.bytes[channel]) - 128) <= 1, "corner channel \(channel) = \(raster.bytes[channel])")
        }
    }

    /// Share of the frame that differs visibly from the background corner pixel — a real
    /// image assertion rather than a PNG byte count, which a blank frame also passes. Per-sample
    /// pixel goldens for this path live in `PixelDiffRealityKitTests`.
    static func modelCoverage(_ image: CGImage) throws -> Double {
        let raster = try PixelDiff.raster(from: image)
        let corner = Array(raster.bytes[0..<3])
        var covered = 0
        for pixel in 0..<raster.pixelCount {
            let base = pixel * 4
            let delta = (0..<3).map { abs(Int(raster.bytes[base + $0]) - Int(corner[$0])) }.max() ?? 0
            if delta > 24 { covered += 1 }
        }
        return Double(covered) / Double(raster.pixelCount)
    }
}
