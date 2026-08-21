import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import GLBPreview

/// In-process thumbnail proof. `qlmanage` can hang against a stale system plugin.
struct StillRenderProofTests {
    @MainActor
    @Test func stillRendererWritesTinyPNG() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("scripts/tiny.glb")
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
                ?? "/tmp/GLBPreview-proof.png"
        )
        try StillRenderer.writePNG(image, to: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: out.path)
        let size = attrs[.size] as? NSNumber
        #expect((size?.intValue ?? 0) > 800)
    }

    /// Committed multi-file sidecar (`cube.gltf` + `cube.bin` + `cube.png`) rendered
    /// end-to-end. It uses standard metal/rough + FLOAT attributes, so it exercises the
    /// live *skip-packing* sidecar path (no temp GLB) that only synthesized temp files
    /// covered before. A solid cube also stays visible from any turntable angle, unlike
    /// the flat `tiny.glb` triangle. Regenerate with `scripts/testdata/cube/make_cube.py`.
    @MainActor
    @Test func cubeSidecarRendersFromCommittedFiles() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("scripts/testdata/cube/cube.gltf")
        try #require(FileManager.default.fileExists(atPath: url.path))

        // Confirm the committed file really lands on the no-pack path.
        let json = try GLBBox.parseJSON(Data(contentsOf: url))
        #expect(!MetalRoughPrepare.needsConversion(json))
        #expect(!RealityPrepare.needsPrepare(json))

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
                ?? "/tmp/GLBPreview-cube-proof.png"
        )
        try StillRenderer.writePNG(image, to: out)
        let attrs = try FileManager.default.attributesOfItem(atPath: out.path)
        let size = attrs[.size] as? NSNumber
        #expect((size?.intValue ?? 0) > 800)
    }
}
