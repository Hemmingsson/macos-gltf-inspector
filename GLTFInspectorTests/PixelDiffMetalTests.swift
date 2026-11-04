import CoreGraphics
import Foundation
import GLTFCore
import Testing
@testable import RendererMetal

/// The native renderer uses exactly the page's recorded cameras, lighting and comparator.
/// Parity is opt-in while the port is incomplete; enabling it asserts every sample without
/// expected failures or relaxed tolerances. Smoke tests remain in the normal test run.
@MainActor
enum PixelDiffMetal {
    static func make(manifest: PixelDiffManifest) async throws -> PixelDiffRun.Render {
        let renderer = try MetalRenderer()
        let look = try PixelDiffWebKit.renderLook(manifest.look)
        return { entry in
            let camera = try PixelDiffRun.camera(of: entry)
            try await renderer.load(url: entry.modelURL)
            return try renderer.still(
                look: look, pose: MetalCameraPose(camera), size: manifest.look.canvasSize
            )
        }
    }
}

extension MetalCameraPose {
    init(_ camera: PixelDiffManifest.Camera) {
        self.init(
            azimuth: camera.azimuth,
            elevation: camera.elevation,
            distance: camera.distance,
            target: SIMD3(Float(camera.target[0]), Float(camera.target[1]), Float(camera.target[2])),
            yfov: camera.yfov,
            znear: camera.znear,
            zfar: camera.zfar
        )
    }
}

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GLTF_METAL_PARITY"] == "1",
    "Native Khronos port parity gate: GLTF_METAL_PARITY=1 ./scripts/dev.sh test -only-testing:GLTFInspectorTests/PixelDiffMetalTests"))
struct PixelDiffMetalTests {
    @Test func everySampleMatchesItsKhronosReference() async throws {
        let manifest = try PixelDiffManifest.load()
        try await PixelDiffRun.expectEverySampleMatches(
            manifest: manifest,
            render: try await PixelDiffMetal.make(manifest: manifest)
        )
    }
}
