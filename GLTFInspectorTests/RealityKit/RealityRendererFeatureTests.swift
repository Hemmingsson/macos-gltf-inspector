import GLTFCore
import RendererRealityKit
import Testing

/// The RealityKit canvas drives all host chrome.
struct RealityRendererFeatureTests {
    @Test func everyFeature() {
        #expect(RealityPreviewCanvas.features == Set(RendererFeature.allCases))
    }
}
