import Foundation
@testable import GLTFCore
@testable import RendererRealityKit
import Testing

/// HDR decode must not require the main actor. `EnvironmentResource(equirectangular:)` stays
/// `@MainActor`; the float ImageIO work does not.
struct PreviewLightingDecodeTests {
    @Test
    func hdrDecodeRunsOffTheMainActor() async throws {
        let url = try #require(KhronosEnvironments.defaultLook.bundledURL)
        let image = await Task.detached {
            #expect(!Thread.isMainThread)
            return EquirectangularImage.load(from: url)
        }.value
        #expect(image != nil)
        #expect((image?.width ?? 0) > 1)
        #expect((image?.height ?? 0) > 1)
    }

    @Test
    func environmentResourceLoadDecodesWithoutOccupyingMainFirst() async throws {
        let url = try #require(KhronosEnvironments.defaultLook.bundledURL)
        let decoded = await PreviewLighting.decodeHDROffMain(from: url)
        #expect(decoded != nil)
    }
}
