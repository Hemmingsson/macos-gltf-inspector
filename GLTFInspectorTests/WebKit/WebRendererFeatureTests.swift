import GLTFCore
import RendererWebKit
import Testing

/// What the web page can drive. The host hides the rest (clip playback, morph sliders, hide/solo).
struct WebRendererFeatureTests {
    @Test func pageFeatures() {
        let features = WebPreviewCanvas.features
        #expect(features.contains(.debugChannels))
        #expect(features.contains(.wireframe))
        #expect(features.contains(.materialVariants))
        #expect(!features.contains(.animationPlayback))
        #expect(!features.contains(.morphTargets))
        #expect(!features.contains(.nodeVisibility))
    }
}
